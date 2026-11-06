import Stripe from "npm:stripe@17.7.0";
import { createClient } from "npm:@supabase/supabase-js@2";

const SITE_URL=(Deno.env.get("SITE_URL")||"https://get-saucy.vercel.app").replace(/\/$/,"");
const cors={"Access-Control-Allow-Origin":SITE_URL,"Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info","Access-Control-Allow-Methods":"POST, OPTIONS","Vary":"Origin"};
function reply(body:unknown,status=200){return new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}})}
function keyFromEnv(name:string,container:string,alternates:string[]=[]){
 const direct=Deno.env.get(name);if(direct)return direct;
 try{const keys=JSON.parse(Deno.env.get(container)||"{}");for(const k of alternates)if(keys[k])return keys[k]}catch{}
 return "";
}
const supabaseAdminKey=()=>keyFromEnv("SUPABASE_SERVICE_ROLE_KEY","SUPABASE_SECRET_KEYS",["default","service_role"]);
const supabasePublicKey=()=>keyFromEnv("SUPABASE_ANON_KEY","SUPABASE_PUBLISHABLE_KEYS",["default","publishable"]);
async function userFromRequest(req:Request){
 const token=(req.headers.get("Authorization")||"").replace(/^Bearer\s+/i,"");
 const url=Deno.env.get("SUPABASE_URL")||"",key=supabasePublicKey();
 if(!token||!url||!key)return null;
 const client=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data,error}=await client.auth.getUser(token);
 return error?null:data.user;
}
async function handleWebhook(req:Request){
 const secret=Deno.env.get("STRIPE_SECRET_KEY")||"",signingSecret=Deno.env.get("STRIPE_WEBHOOK_SECRET")||"";
 if(!secret||!signingSecret)return new Response("Billing is not configured.",{status:503});
 const signature=req.headers.get("stripe-signature");if(!signature)return new Response("Missing Stripe signature.",{status:400});
 const stripe=new Stripe(secret),cryptoProvider=Stripe.createSubtleCryptoProvider();
 let event:any;
 try{event=await stripe.webhooks.constructEventAsync(await req.text(),signature,signingSecret,undefined,cryptoProvider)}
 catch{return new Response("Invalid Stripe signature.",{status:400})}
 const adminKey=supabaseAdminKey(),url=Deno.env.get("SUPABASE_URL")||"";
 if(!adminKey||!url)return new Response("Subscription storage is not configured.",{status:503});
 const admin=createClient(url,adminKey,{auth:{persistSession:false,autoRefreshToken:false}});
 try{
  let subscriptionId:string|null=null,fallbackUserId="";
  if(event.type==="checkout.session.completed"){
   const session=event.data.object;
   subscriptionId=typeof session.subscription==="string"?session.subscription:session.subscription?.id||null;
   fallbackUserId=session.client_reference_id||session.metadata?.supabase_user_id||"";
  }else if(["customer.subscription.created","customer.subscription.updated","customer.subscription.deleted"].includes(event.type)){
   subscriptionId=event.data.object.id;
  }else if(event.type==="invoice.payment_failed"){
   const value=event.data.object.subscription;
   subscriptionId=typeof value==="string"?value:value?.id||null;
  }else return Response.json({received:true});
  if(!subscriptionId)return Response.json({received:true});
  const response=await fetch("https://api.stripe.com/v1/subscriptions/"+encodeURIComponent(subscriptionId),{headers:{Authorization:"Bearer "+secret}});
  if(!response.ok)throw new Error("Subscription lookup failed.");
  const subscription=await response.json();
  const userId=subscription.metadata?.supabase_user_id||fallbackUserId;
  if(!userId)return Response.json({received:true,ignored:"missing_member_id"});
  const {data:prior,error:priorError}=await admin.from("user_subscriptions").select("stripe_subscription_id,status").eq("user_id",userId).maybeSingle();
  if(priorError)throw priorError;
  const billable=["active","trialing","past_due","unpaid","incomplete"].includes(prior?.status||"");
  if(prior?.stripe_subscription_id&&prior.stripe_subscription_id!==subscription.id&&billable)return Response.json({received:true,ignored:"older_subscription"});
  const customer=typeof subscription.customer==="string"?subscription.customer:subscription.customer?.id||null;
  const price=subscription.items?.data?.[0]?.price?.id||null;
  const periodEnd=subscription.items?.data?.[0]?.current_period_end??subscription.current_period_end??null;
  const {error}=await admin.from("user_subscriptions").upsert({
   user_id:userId,stripe_customer_id:customer,stripe_subscription_id:subscription.id,price_id:price,
   status:subscription.status,current_period_end:periodEnd?new Date(periodEnd*1000).toISOString():null,
   cancel_at_period_end:Boolean(subscription.cancel_at_period_end),updated_at:new Date().toISOString()
  },{onConflict:"user_id"});
  if(error)throw error;
  return Response.json({received:true});
 }catch(error){
  console.error("Stripe webhook processing failed:",error?.message||"unknown error");
  return new Response("Webhook processing failed.",{status:500});
 }
}
Deno.serve(async(req)=>{
 if(req.headers.has("stripe-signature"))return await handleWebhook(req);
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.headers.get("origin")&&req.headers.get("origin")!==SITE_URL)return reply({error:"Origin not allowed."},403);
 if(req.method!=="POST")return reply({error:"Method not allowed."},405);
 let body:any;try{body=await req.json()}catch{return reply({error:"Invalid request."},400)}
 if(body.action==="status"){
  const ready=Boolean(Deno.env.get("STRIPE_SECRET_KEY")&&Deno.env.get("STRIPE_VIP_PRICE_ID")&&Deno.env.get("STRIPE_WEBHOOK_SECRET")&&supabaseAdminKey());
  if(!ready)return reply({enabled:false});
  const admin=createClient(Deno.env.get("SUPABASE_URL")||"",supabaseAdminKey(),{auth:{persistSession:false,autoRefreshToken:false}});
  const {error}=await admin.from("user_subscriptions").select("user_id").limit(1);
  return reply({enabled:!error});
 }
 const user=await userFromRequest(req);if(!user)return reply({error:"Sign in to continue."},401);
 const secret=Deno.env.get("STRIPE_SECRET_KEY")||"",priceId=Deno.env.get("STRIPE_VIP_PRICE_ID")||"";
 const adminKey=supabaseAdminKey(),url=Deno.env.get("SUPABASE_URL")||"";
 if(!secret||!Deno.env.get("STRIPE_WEBHOOK_SECRET")||!priceId||!adminKey||!url)return reply({error:"VIP billing setup is incomplete."},503);
 const admin=createClient(url,adminKey,{auth:{persistSession:false,autoRefreshToken:false}});
 if(body.action==="checkout"){
  const {data:membership,error}=await admin.from("user_subscriptions").select("stripe_customer_id,status").eq("user_id",user.id).maybeSingle();
  if(error)return reply({error:"VIP membership setup is incomplete."},503);
  if(membership&&["active","trialing","past_due","unpaid","incomplete"].includes(membership.status))return reply({error:"You already have a membership. Open Manage VIP billing instead."},409);
  const priceResponse=await fetch("https://api.stripe.com/v1/prices/"+encodeURIComponent(priceId),{headers:{Authorization:"Bearer "+secret}});
  if(!priceResponse.ok)return reply({error:"The VIP price is not configured correctly."},503);
  const price=await priceResponse.json();
  if(price.unit_amount!==499||price.currency!=="usd"||price.recurring?.interval!=="month"||(price.recurring?.interval_count??1)!==1)return reply({error:"VIP must be configured as $4.99 USD per month."},503);
  const form=new URLSearchParams();form.set("mode","subscription");form.set("line_items[0][price]",priceId);form.set("line_items[0][quantity]","1");
  form.set("success_url",SITE_URL+"/community.html?vip=success");form.set("cancel_url",SITE_URL+"/community.html?vip=cancelled");
  form.set("client_reference_id",user.id);form.set("metadata[supabase_user_id]",user.id);form.set("subscription_data[metadata][supabase_user_id]",user.id);
  if(membership?.stripe_customer_id)form.set("customer",membership.stripe_customer_id);else if(user.email)form.set("customer_email",user.email);
  const response=await fetch("https://api.stripe.com/v1/checkout/sessions",{method:"POST",headers:{Authorization:"Bearer "+secret,"Content-Type":"application/x-www-form-urlencoded"},body:form});
  const session=await response.json();if(!response.ok||!session.url)return reply({error:"Secure checkout could not be started."},502);
  return reply({url:session.url});
 }
 if(body.action==="portal"){
  const {data:membership,error}=await admin.from("user_subscriptions").select("stripe_customer_id").eq("user_id",user.id).maybeSingle();
  if(error)return reply({error:"VIP membership setup is incomplete."},503);
  if(!membership?.stripe_customer_id)return reply({error:"No billing account is linked to this profile."},404);
  const form=new URLSearchParams();form.set("customer",membership.stripe_customer_id);form.set("return_url",SITE_URL+"/community.html");
  const response=await fetch("https://api.stripe.com/v1/billing_portal/sessions",{method:"POST",headers:{Authorization:"Bearer "+secret,"Content-Type":"application/x-www-form-urlencoded"},body:form});
  const portal=await response.json();if(!response.ok||!portal.url)return reply({error:"Billing management could not be opened."},502);
  return reply({url:portal.url});
 }
 return reply({error:"Unsupported billing action."},400);
});
