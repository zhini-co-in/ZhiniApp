// lib/controllers/serviceTicketController.js
//
// THIS IS THE FULL, FINAL FILE — replace your entire
// controllers/serviceTicketController.js content with this.
//
// Two handlers:
//   1. createServiceTicket  — your original logic, unchanged, + one new
//      `source` field so we know if a ticket was created manually.
//   2. updateTicketStatus   — your ORIGINAL Wekan-integrated version
//      (card move + list mapping), with WhatsApp notifications added.
//      Same function name, same route (/service/update-status) — no
//      router changes needed for this one.

import {
  ticketAcceptedMessage,
  technicianReachedMessage,
  waitingForPartsMessage,
  serviceCompletedMessage,
  appPromoMessage,
} from "../utils/whatsappTemplates.js";
import { sendWhatsAppText } from "../utils/sendWhatsAppMessage.js";
// For production: swap sendWhatsAppText -> sendWhatsAppTemplate once your
// Meta message templates are approved (see sendWhatsAppMessage.js comments).

// ===========================================================================
// 1. createServiceTicket
// ===========================================================================
export const createServiceTicket = async (c) => {
  try {
    let body = {};
    try {
      body = await c.req.json();
    } catch (_) {
      body = await c.req.parseBody();
    }

    const customerName = body.customerName || body.customer_name;
    const custNumber = body.cust_number || body.customerPhone || body.mobile;
    const address = body.address;
    const description = body.description || body.notes || "Service Request";
    const providerMobile = body.providerMobile;
    const source = body.source === "MANUAL" ? "MANUAL" : "APP"; // 🆕

    const rawAvailableTime = body.availableTime || body.preferredTime || body.timeSlot;
    const availableTime = rawAvailableTime ? String(rawAvailableTime).trim() : "Flexible / Not specified";

    if (!customerName || !custNumber || !address || !providerMobile) {
      return c.json({
        success: false,
        message: "Missing required fields: customerName, cust_number, address, and providerMobile are required.",
      }, 400);
    }

    const ticketResult = await withDatabase(mongoUri, async (db) => {
      const providerCollection = db.collection("service-providers");
      const wekanServiceCollection = db.collection("wekan-services");

      const cleanProviderMobile = providerMobile.trim();

      let provider = await providerCollection.findOne({ mobile: cleanProviderMobile });

      let boardId = provider?.wekanBoardId;
      let newListId = provider?.wekanLists?.["New"];

      if (!boardId || !newListId) {
        console.warn(`⚠️ Board info missing for provider '${cleanProviderMobile}'. Provisioning now...`);
        const boardResult = await createProviderBoard(cleanProviderMobile);
        boardId = boardResult.boardId;
        newListId = boardResult.lists["New"];

        if (provider) {
          await providerCollection.updateOne(
            { mobile: cleanProviderMobile },
            {
              $set: {
                wekanBoardId: boardId,
                wekanLists: boardResult.lists,
                updatedAt: new Date()
              }
            }
          );
        }
      }

      const cardTitle = `Ticket: ${customerName.trim()} (${custNumber.trim()})`;
      const cardDescription = `Customer Name: ${customerName.trim()}\nCustomer Phone: ${custNumber.trim()}\nAddress: ${address.trim()}\nAvailable Time: ${availableTime}\nDescription: ${description.trim()}`;

      const cardId = await createServiceCard(boardId, newListId, {
        title: cardTitle,
        description: cardDescription,
        customerPhone: custNumber.trim(),
      });

      const ticketRecord = {
        ticketId: `TICK-${Date.now()}`,
        assignedTo: cleanProviderMobile,
        customerDetails: {
          name: customerName.trim(),
          phone: custNumber.trim(),
          address: address.trim(),
        },
        serviceDetails: {
          description: description.trim(),
          availableTime: availableTime,
        },
        wekan: {
          boardId: boardId,
          cardId: cardId,
          listId: newListId,
        },
        status: "NEW",
        source, // 🆕 'MANUAL' or 'APP' — gates WhatsApp notifications below
        createdAt: new Date(),
        updatedAt: new Date(),
      };

      await wekanServiceCollection.insertOne(ticketRecord);
      return ticketRecord;
    });

    return c.json({
      success: true,
      message: "Ticket created and assigned to service provider.",
      data: ticketResult,
    }, 201);

  } catch (error) {
    console.error("❌ Create Service Ticket Controller Error:", error);

    return c.json({
      success: false,
      message: "Failed to create service ticket",
      error: error.message,
    }, 500);
  }
};

// ===========================================================================
// 2. updateTicketStatus  (your original Wekan logic + WhatsApp added)
// ===========================================================================
const STATUS_TO_WEKAN_LIST = {
  "NEW": "New",
  "ACCEPTED": "Accepted",
  "REJECTED": "Rejected",
  "IN_PROGRESS": "In Progress",
  "WAITING_FOR_PARTS": "Waiting for Parts",
  "COMPLETED": "Completed"
};

// Fires the right customer WhatsApp message for a status change.
// Never throws — a WhatsApp hiccup should never fail the status update.
async function notifyCustomerIfManual(ticketDoc, normalizedStatus) {
  console.log(`🔎 [WhatsApp debug] ticketId=${ticketDoc?.ticketId} source=${ticketDoc?.source} status=${normalizedStatus}`); // 🆕 TEMP DEBUG LOG

  if (!ticketDoc || ticketDoc.source !== "MANUAL") {
    console.log(`🔎 [WhatsApp debug] Skipping — source is not 'MANUAL' (it's '${ticketDoc?.source}')`); // 🆕
    return;
  }

  const customerPhone = ticketDoc.customerDetails?.phone;
  if (!customerPhone) {
    console.warn(`⚠️ No customer phone on ticket ${ticketDoc.ticketId}, skipping WhatsApp.`);
    return;
  }

  const customerName = ticketDoc.customerDetails?.name || "Customer";
  const providerName = ticketDoc.assignedTo || "your technician";
  const appliance = ticketDoc.serviceDetails?.description || "your appliance";
  const address = ticketDoc.customerDetails?.address || "";
  const availableTime = ticketDoc.serviceDetails?.availableTime || "";
  const ticketId = ticketDoc.ticketId;

  let message = null;
  switch (normalizedStatus) {
    case "ACCEPTED":
      message = ticketAcceptedMessage({ customerName, ticketId, providerName, appliance, address, availableTime });
      break;
    case "REACHED":
      message = technicianReachedMessage({ customerName, ticketId, providerName });
      break;
    case "WAITING_FOR_PARTS":
      message = waitingForPartsMessage({ customerName, ticketId });
      break;
    case "COMPLETED":
      message = serviceCompletedMessage({ customerName, ticketId, providerName });
      break;
    // REJECTED: no customer message by default.
  }

  if (message) {
    const sendResult = await sendWhatsAppText(customerPhone, message);
    if (!sendResult.success) {
      console.error(`❌ WhatsApp (${normalizedStatus}) failed for ticket ${ticketId}:`, sendResult.error);
    }
  }

  // Final step of the flow: right after COMPLETED, also nudge the customer
  // to install/use the app — sent as a separate follow-up message.
  if (normalizedStatus === "COMPLETED") {
    const promoResult = await sendWhatsAppText(customerPhone, appPromoMessage({ customerName }));
    if (!promoResult.success) {
      console.error(`❌ WhatsApp (app promo) failed for ticket ${ticketId}:`, promoResult.error);
    }
  }
}

export const updateTicketStatus = async (c) => {
  try {
    let body = {};
    try {
      body = await c.req.json();
    } catch (_) {
      body = await c.req.parseBody();
    }

    const { ticketId, newStatus } = body;

    if (!ticketId || !newStatus) {
      return c.json({
        success: false,
        message: "Missing required fields: ticketId and newStatus are required."
      }, 400);
    }

    const normalizedStatus = String(newStatus).trim().toUpperCase();

    // --- 🆕 REACHED: notify-only event, no Wekan move, no status overwrite ---
    if (normalizedStatus === "REACHED") {
      const ticketDoc = await withDatabase(mongoUri, async (db) => {
        const wekanServiceCollection = db.collection("wekan-services");
        const ticket = await wekanServiceCollection.findOne({ ticketId: ticketId.trim() });
        if (!ticket) throw new Error(`Ticket '${ticketId}' not found in database.`);

        await wekanServiceCollection.updateOne(
          { ticketId: ticketId.trim() },
          { $set: { reachedAt: new Date(), updatedAt: new Date() } }
        );
        return ticket;
      });

      await notifyCustomerIfManual(ticketDoc, "REACHED");

      return c.json({
        success: true,
        message: `Ticket ${ticketId} marked as reached.`,
      }, 200);
    }

    // --- existing Wekan-backed statuses ---
    const targetListName = STATUS_TO_WEKAN_LIST[normalizedStatus];
    if (!targetListName) {
      return c.json({
        success: false,
        message: `Invalid status '${newStatus}'. Allowed statuses: ${[...Object.keys(STATUS_TO_WEKAN_LIST), "REACHED"].join(", ")}`
      }, 400);
    }

    const updatedTicket = await withDatabase(mongoUri, async (db) => {
      const wekanServiceCollection = db.collection("wekan-services");
      const providerCollection = db.collection("service-providers");

      const ticket = await wekanServiceCollection.findOne({ ticketId: ticketId.trim() });
      if (!ticket) {
        throw new Error(`Ticket '${ticketId}' not found in database.`);
      }

      const { boardId, cardId, listId: currentListId } = ticket.wekan;
      const assignedProviderMobile = ticket.assignedTo;

      let provider = await providerCollection.findOne({ mobile: assignedProviderMobile });
      let newListId = provider?.wekanLists?.[targetListName];

      if (!newListId) {
        const boardResult = await createProviderBoard(assignedProviderMobile);
        newListId = boardResult.lists[targetListName];
      }
      if (!newListId) {
        throw new Error(`Target list '${targetListName}' could not be resolved on Wekan Board ${boardId}`);
      }

      await moveCardToList(boardId, currentListId, cardId, newListId);

      const updateResult = await wekanServiceCollection.findOneAndUpdate(
        { ticketId: ticketId.trim() },
        {
          $set: {
            status: normalizedStatus,
            "wekan.listId": newListId,
            updatedAt: new Date()
          }
        },
        { returnDocument: "after" }
      );

      return updateResult;
    });

    // 🆕 fire WhatsApp (gated on source === 'MANUAL', handled inside)
    await notifyCustomerIfManual(updatedTicket, normalizedStatus);

    return c.json({
      success: true,
      message: `Ticket ${ticketId} updated to '${normalizedStatus}' successfully.`,
      data: updatedTicket
    }, 200);

  } catch (error) {
    console.error("❌ Update Ticket Status Controller Error:", error);
    return c.json({
      success: false,
      message: "Failed to update ticket status",
      error: error.message
    }, 500);
  }
};