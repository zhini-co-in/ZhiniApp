// lib/utils/whatsappTemplates.js
//
// Central place for every customer-facing WhatsApp message in the ticket
// lifecycle. Keep the TEXT versions here for local dev / plain-text sending.
// For production, create matching APPROVED TEMPLATES in Meta Business
// Manager with the SAME variable order, then use sendWhatsAppTemplate()
// with these same param arrays instead.

function ticketAcceptedMessage({ customerName, ticketId, providerName, appliance, address, availableTime }) {
  return (
    `Hi ${customerName}, your service request has been *accepted*. ✅\n\n` +
    `*Ticket ID:* ${ticketId}\n` +
    `*Appliance/Issue:* ${appliance}\n` +
    `*Address:* ${address}\n` +
    `*Preferred time:* ${availableTime}\n` +
    `*Technician:* ${providerName}\n\n` +
    `We'll notify you here as the status updates.`
  );
}

function technicianReachedMessage({ customerName, ticketId, providerName }) {
  return (
    `Hi ${customerName}, your technician *${providerName}* has *reached* your location ` +
    `for Ticket ${ticketId}. 🚗`
  );
}

function waitingForPartsMessage({ customerName, ticketId }) {
  return (
    `Hi ${customerName}, your service (Ticket ${ticketId}) is currently *waiting for spare parts*. ⏳ ` +
    `We'll update you once the part arrives and work resumes.`
  );
}

function serviceCompletedMessage({ customerName, ticketId, providerName }) {
  return (
    `Hi ${customerName}, your service (Ticket ${ticketId}) has been marked *completed* by ${providerName}. ✅\n\n` +
    `Thank you for using our service!`
  );
}

function appPromoMessage({ customerName }) {
  return (
    `Hi ${customerName}, if you'd like to track future service requests, view warranty info, ` +
    `and book service faster next time — install our app here: <APP_DOWNLOAD_LINK>`
  );
}

module.exports = {
  ticketAcceptedMessage,
  technicianReachedMessage,
  waitingForPartsMessage,
  serviceCompletedMessage,
  appPromoMessage,
};