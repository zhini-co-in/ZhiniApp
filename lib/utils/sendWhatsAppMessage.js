// lib/utils/sendWhatsAppMessage.js
//
// Meta WhatsApp Cloud API wrapper.
// Env vars needed (add to your .env / deployment secrets):
//   WHATSAPP_TOKEN            - permanent access token from Meta Business Manager
//   WHATSAPP_PHONE_NUMBER_ID  - the "Phone number ID" of your WhatsApp Business number
//   WHATSAPP_API_VERSION      - e.g. "v20.0" (optional, defaults below)
//
// IMPORTANT: Meta only lets you send free-form TEXT messages if the
// customer messaged you first within the last 24 hours. Since these
// notifications are sent by the PROVIDER (business-initiated), you
// need an APPROVED MESSAGE TEMPLATE for each of these to work reliably
// in production:
//   - ticket_created / ticket_accepted
//   - technician_reached
//   - waiting_for_parts
//   - service_completed
//   - app_promo
//
// Create these templates in Meta Business Manager -> WhatsApp Manager ->
// Message Templates, get them approved (usually a few hours), then use
// sendWhatsAppTemplate() below. Until they're approved, you can test with
// sendWhatsAppText() on numbers that have messaged your business number
// in the last 24h (e.g. your own test number).

const WHATSAPP_API_VERSION = process.env.WHATSAPP_API_VERSION || "v20.0";
const GRAPH_URL = `https://graph.facebook.com/${WHATSAPP_API_VERSION}`;

function normalizeIndianNumber(rawNumber) {
  // Ensures numbers are in E.164 without '+' as Meta's API expects,
  // e.g. "9876543210" -> "919876543210"
  let n = String(rawNumber).replace(/\D/g, "");
  if (n.length === 10) n = `91${n}`;
  if (n.startsWith("0")) n = `91${n.slice(1)}`;
  return n;
}

async function callWhatsAppApi(payload) {
  const token = process.env.WHATSAPP_TOKEN;
  const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID;

  if (!token || !phoneNumberId) {
    console.error("❌ WhatsApp credentials missing (WHATSAPP_TOKEN / WHATSAPP_PHONE_NUMBER_ID)");
    return { success: false, error: "WhatsApp not configured" };
  }

  try {
    const res = await fetch(`${GRAPH_URL}/${phoneNumberId}/messages`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    const data = await res.json();
    if (!res.ok) {
      console.error("❌ WhatsApp API error:", JSON.stringify(data));
      return { success: false, error: data?.error?.message || "WhatsApp send failed" };
    }
    return { success: true, data };
  } catch (err) {
    console.error("❌ WhatsApp send exception:", err.message);
    return { success: false, error: err.message };
  }
}

/**
 * Send a plain text WhatsApp message.
 * Only works within the 24h customer-service window (or sandbox/test numbers).
 */
async function sendWhatsAppText(to, message) {
  const payload = {
    messaging_product: "whatsapp",
    to: normalizeIndianNumber(to),
    type: "text",
    text: { preview_url: false, body: message },
  };
  return callWhatsAppApi(payload);
}

/**
 * Send an approved WhatsApp message TEMPLATE (works anytime, no 24h window issue).
 * `params` is an ordered array of strings mapped to {{1}}, {{2}}... in the template body.
 */
async function sendWhatsAppTemplate(to, templateName, params = [], languageCode = "en") {
  const payload = {
    messaging_product: "whatsapp",
    to: normalizeIndianNumber(to),
    type: "template",
    template: {
      name: templateName,
      language: { code: languageCode },
      components: params.length
        ? [
            {
              type: "body",
              parameters: params.map((p) => ({ type: "text", text: String(p) })),
            },
          ]
        : [],
    },
  };
  return callWhatsAppApi(payload);
}

module.exports = { sendWhatsAppText, sendWhatsAppTemplate, normalizeIndianNumber };