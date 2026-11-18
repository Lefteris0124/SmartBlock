import Stripe from 'npm:stripe@^23'
import { createClient } from 'npm:@supabase/supabase-js@2'

const stripeKey = Deno.env.get('STRIPE_SECRET_KEY')
const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET')
const supabaseUrl = Deno.env.get('SUPABASE_URL')
const secretMap = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}') as Record<string, string>
const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? secretMap.default

let stripe: Stripe
let supabaseAdmin: ReturnType<typeof createClient>
const cryptoProvider = Stripe.createSubtleCryptoProvider()

async function paymentMethodFor(paymentIntentId: string): Promise<string> {
  const intent = await stripe.paymentIntents.retrieve(paymentIntentId, { expand: ['latest_charge'] })
  const charge = typeof intent.latest_charge === 'string' || !intent.latest_charge
    ? null
    : intent.latest_charge
  const wallet = charge?.payment_method_details?.card?.wallet?.type
  if (wallet === 'apple_pay') return 'apple_pay'
  if (wallet === 'google_pay') return 'google_pay'
  return 'card'
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return new Response('Method not allowed.', { status: 405 })
  if (!stripeKey || !webhookSecret || !supabaseUrl || !supabaseKey) {
    return new Response('Stripe webhook secrets are not configured.', { status: 503 })
  }
  if (!stripeKey.startsWith('sk_test_')) {
    return new Response('Stripe webhook is locked to test mode until live payments are explicitly enabled.', { status: 503 })
  }
  stripe = new Stripe(stripeKey)
  supabaseAdmin = createClient(supabaseUrl, supabaseKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })
  const signature = request.headers.get('stripe-signature')
  if (!signature) return new Response('Missing Stripe signature.', { status: 400 })

  let event: Stripe.Event
  try {
    event = await stripe.webhooks.constructEventAsync(
      await request.text(),
      signature,
      webhookSecret,
      undefined,
      cryptoProvider,
    )
  } catch (error) {
    console.error('Stripe webhook signature verification failed:', error)
    return new Response('Invalid signature.', { status: 400 })
  }

  if (!['checkout.session.completed', 'checkout.session.async_payment_succeeded'].includes(event.type)) {
    return Response.json({ received: true })
  }

  const session = event.data.object as Stripe.Checkout.Session
  if (session.mode !== 'payment' || session.payment_status !== 'paid') {
    return Response.json({ received: true })
  }
  const paymentId = session.metadata?.smartblock_payment_id
  const paymentIntentId = typeof session.payment_intent === 'string'
    ? session.payment_intent
    : session.payment_intent?.id
  if (!paymentId || !paymentIntentId || session.amount_total == null || !session.currency) {
    return new Response('Missing payment metadata.', { status: 400 })
  }

  let method: string
  try {
    method = await paymentMethodFor(paymentIntentId)
  } catch (error) {
    console.error('Could not retrieve Stripe payment details; requesting webhook retry:', error)
    return new Response('Could not retrieve payment details.', { status: 500 })
  }

  const { error } = await supabaseAdmin.rpc('complete_property_online_payment', {
      p_payment_id: paymentId,
      p_checkout_session_id: session.id,
      p_payment_intent_id: paymentIntentId,
      p_amount_paid_minor: session.amount_total,
      p_currency: session.currency.toUpperCase(),
      p_payment_method: method,
      p_paid_at: new Date(event.created * 1000).toISOString(),
    })
  if (!error) return Response.json({ received: true })

  const refundRequired = [
    'Balance changed after Checkout started',
    'Charge entry no longer exists',
    'Rent installment no longer exists',
    'Stripe payment amount or currency does not match',
  ].some((reason) => error.message.includes(reason))
  if (!refundRequired) {
    console.error('Could not reconcile Stripe payment; requesting webhook retry:', error)
    return new Response('Could not reconcile payment.', { status: 500 })
  }

  try {
    await stripe.refunds.create(
      { payment_intent: paymentIntentId, metadata: { smartblock_payment_id: paymentId, reason: 'balance_changed' } },
      { idempotencyKey: `smartblock-refund-${paymentIntentId}` },
    )
    const { error: refundRecordError } = await supabaseAdmin.rpc('mark_property_online_payment_refunded', {
      p_payment_id: paymentId,
      p_checkout_session_id: session.id,
      p_payment_intent_id: paymentIntentId,
    })
    if (refundRecordError) throw refundRecordError
    return Response.json({ received: true, refunded: true })
  } catch (refundError) {
    console.error('Automatic refund failed; Stripe will retry the webhook:', refundError)
    return new Response('Payment reconciliation and refund failed.', { status: 500 })
  }
})

