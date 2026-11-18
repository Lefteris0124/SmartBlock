import Stripe from 'npm:stripe@^23'
import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info, x-supabase-api-version',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
}

const json = (body: Record<string, unknown>, status = 200, origin = '') =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      ...(origin ? { 'Access-Control-Allow-Origin': origin } : {}),
      Vary: 'Origin',
    },
  })

Deno.serve(async (request) => {
  const origin = request.headers.get('origin') ?? ''
  const allowedOrigins = (Deno.env.get('SMARTBLOCK_ALLOWED_ORIGINS') ?? 'https://lefteris0124.github.io')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean)

  if (request.method === 'OPTIONS') {
    if (!allowedOrigins.includes(origin)) return new Response(null, { status: 403 })
    return new Response('ok', {
      headers: { ...corsHeaders, 'Access-Control-Allow-Origin': origin, Vary: 'Origin' },
    })
  }
  if (request.method !== 'POST') return json({ error: 'Method not allowed.' }, 405)
  if (origin && !allowedOrigins.includes(origin)) return json({ error: 'Origin not allowed.' }, 403, origin)

  const authorization = request.headers.get('authorization')
  if (!authorization?.startsWith('Bearer ')) return json({ error: 'Sign in to continue.' }, 401, origin)

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const publishableKeyMap = JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS') ?? '{}') as Record<string, string>
  const publishableKey = Deno.env.get('SUPABASE_ANON_KEY')
    ?? Deno.env.get('SUPABASE_PUBLISHABLE_KEY')
    ?? publishableKeyMap.default
  const stripeKey = Deno.env.get('STRIPE_SECRET_KEY')
  if (!supabaseUrl || !publishableKey || !stripeKey) {
    return json({ error: 'Online payments are not configured yet.' }, 503, origin)
  }
  if (!stripeKey.startsWith('sk_test_')) {
    return json({ error: 'Online payments are locked to Stripe test mode until live payments are explicitly enabled.' }, 503, origin)
  }

  const supabase = createClient(supabaseUrl, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { autoRefreshToken: false, persistSession: false },
  })
  const { data: userResult, error: userError } = await supabase.auth.getUser()
  if (userError || !userResult.user) return json({ error: 'Your session has expired. Sign in again.' }, 401, origin)

  let body: { target_type?: string; target_id?: string }
  try {
    body = await request.json()
  } catch {
    return json({ error: 'Invalid request.' }, 400, origin)
  }
  if (!['charge', 'rent'].includes(body.target_type ?? '') || !body.target_id) {
    return json({ error: 'Invalid payment target.' }, 400, origin)
  }

  const { data: payment, error: prepareError } = await supabase.rpc('prepare_property_online_payment', {
    p_target_type: body.target_type,
    p_target_id: body.target_id,
  })
  if (prepareError || !payment) {
    return json({ error: prepareError?.message ?? 'This balance cannot be paid online.' }, 400, origin)
  }

  const stripe = new Stripe(stripeKey)
  if (payment.stripe_checkout_session_id) {
    try {
      const existing = await stripe.checkout.sessions.retrieve(payment.stripe_checkout_session_id)
      if (existing.status === 'open' && existing.url) return json({ url: existing.url }, 200, origin)
      if (existing.status === 'complete') {
        return json({ error: 'The payment is being confirmed. Refresh the balance in a moment.' }, 409, origin)
      }
      if (existing.status === 'expired') {
        const { error } = await supabase.rpc('expire_property_checkout_session', { p_payment_id: payment.id })
        if (error) return json({ error: 'The previous checkout could not be closed. Try again shortly.' }, 409, origin)
      }
    } catch (error) {
      console.error('Could not reuse prior Checkout Session:', error)
      return json({ error: 'Could not verify the previous checkout. Try again shortly.' }, 502, origin)
    }
  }
  if (payment.status === 'creating' && payment.is_new !== true && payment.stripe_checkout_session_id == null) {
    return json({ error: 'Payment setup is already in progress. Try again in a moment.' }, 409, origin)
  }

  const returnUrl = Deno.env.get('SMARTBLOCK_RETURN_URL') ?? 'https://lefteris0124.github.io/SmartBlock/'
  const targetLabel = body.target_type === 'rent' ? 'Ενοίκιο SmartBlock' : 'Κοινόχρηστα SmartBlock'
  const amountCents = Math.round(Number(payment.amount) * 100)
  if (!Number.isSafeInteger(amountCents) || amountCents <= 0) {
    return json({ error: 'Invalid outstanding balance.' }, 400, origin)
  }

  try {
    const checkout = await stripe.checkout.sessions.create({
      mode: 'payment',
      integration_identifier: 'smartblock_property_payments_web_v1',
      line_items: [{
        price_data: {
          currency: 'eur',
          product_data: { name: payment.description || targetLabel },
          unit_amount: amountCents,
        },
        quantity: 1,
      }],
      customer_email: userResult.user.email ?? undefined,
      client_reference_id: payment.id,
      metadata: {
        smartblock_payment_id: payment.id,
        smartblock_target_type: body.target_type,
        smartblock_target_id: body.target_id,
      },
      payment_intent_data: {
        metadata: {
          smartblock_payment_id: payment.id,
          smartblock_target_type: body.target_type,
          smartblock_target_id: body.target_id,
        },
      },
      success_url: `${returnUrl}?checkout=success&session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${returnUrl}?checkout=cancelled`,
      expires_at: Math.floor(Date.now() / 1000) + 60 * 60,
    })
    if (!checkout.url) throw new Error('Stripe did not return a Checkout URL.')

    const { error: attachError } = await supabase.rpc('attach_property_checkout_session', {
      p_payment_id: payment.id,
      p_checkout_session_id: checkout.id,
      p_expires_at: new Date(checkout.expires_at * 1000).toISOString(),
    })
    if (attachError) {
      await stripe.checkout.sessions.expire(checkout.id)
      await supabase.rpc('fail_property_checkout_session', { p_payment_id: payment.id })
      return json({ error: 'Could not prepare the payment. Please try again.' }, 500, origin)
    }
    return json({ url: checkout.url }, 200, origin)
  } catch (error) {
    await supabase.rpc('fail_property_checkout_session', { p_payment_id: payment.id })
    console.error('Stripe Checkout creation failed:', error)
    return json({ error: 'Could not start checkout. Please try again.' }, 502, origin)
  }
})

