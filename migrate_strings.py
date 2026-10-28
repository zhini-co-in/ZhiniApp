#!/usr/bin/env python3
"""
migrate_strings.py  -  run from the project root (the folder that has lib/).

  python3 migrate_strings.py

What it does
  1. Reads lib/constants/app_strings.dart and finds every `static const String`.
  2. In the 5 screens, replaces the matching quoted text with AppStrings.<name>.
  3. Replaces the text that has variables ($name, ${count}) with the AppStrings methods.
  4. Adds `import 'constants/app_strings.dart';`.
  5. Prints the lines that are still hardcoded, so you can fix them by hand.

Safe to re-run: already-replaced text is not touched again.
"""
import re
import sys
from pathlib import Path

LIB = Path("lib")
STRINGS_FILE = LIB / "constants" / "app_strings.dart"
TARGETS = [
    "home_tab.dart",
    "devices_tab.dart",
    "scan_tab.dart",
    "service_tab.dart",
    "profile_tab.dart",
]

# ---------------------------------------------------------------------
# 1. Parse AppStrings constants  ->  { 'quoted token': name }
# ---------------------------------------------------------------------
if not STRINGS_FILE.exists():
    sys.exit("lib/constants/app_strings.dart illa. Mudhalla antha file ah vainga.")

src = STRINGS_FILE.read_text(encoding="utf-8")
pat = re.compile(
    r"static const String (\w+) =\s*('(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\");"
)

token_to_name = {}
for name, token in pat.findall(src):
    if name in ("appName", "supportEmail", "supportEmailSubject"):
        continue
    if token in token_to_name:
        # prefer a non-"tab" name when two names share the same text
        if token_to_name[token].startswith("tab") and not name.startswith("tab"):
            token_to_name[token] = name
        continue
    token_to_name[token] = name

# Single-word texts ('All', 'Warranty', 'Open'...) are also used as LOGIC KEYS
# in the code, so they are replaced ONLY inside these display contexts.
CONTEXTS = (
    r"Text\(|'label':|\?\?|_sectionHeader\(|chip\(|hint:|hintText:|title:|"
    r"_openComingSoon\(|badgeText =|_suggestionChip\(|_snack\(|_showSnack\("
)

# ---------------------------------------------------------------------
# 2. Text with variables  (exact source  ->  replacement)
# ---------------------------------------------------------------------
DYNAMIC = [
    # ---- home_tab ----
    (r"""'Devices (${stats['devices']})'""", r"""AppStrings.devicesCount(stats['devices']!)"""),
    (r"""'Valid till ${_fmtDate(expiry)}'""", r"""AppStrings.validTill(_fmtDate(expiry))"""),
    (r"""'Expired on ${_fmtDate(expiry)}'""", r"""AppStrings.expiredOn(_fmtDate(expiry))"""),
    (r"""'$product added ✅'""", r"""AppStrings.applianceAdded(product)"""),
    (r"""'$count nearby'""", r"""AppStrings.nearbyCount(count)"""),
    (r"""'Default devices (${allDevices.length})'""", r"""AppStrings.defaultDevices(allDevices.length)"""),
    (r"""'+${allDevices.length - 5} more'""", r"""AppStrings.moreCount(allDevices.length - 5)"""),
    (r"""'Home ${index + 1}'""", r"""AppStrings.homeN(index + 1)"""),
    (r"""'Home ${_homes.length + 1}'""", r"""AppStrings.homeN(_homes.length + 1)"""),
    (r"""current == null ? 'Select' :""", r"""current == null ? AppStrings.select :"""),
    (r"""'${stats['devices']}', 'Appliances',""", r"""'${stats['devices']}', AppStrings.statAppliances,"""),
    (r"""'${stats['attention']}', 'Attention',""", r"""'${stats['attention']}', AppStrings.statAttention,"""),
    (r"""AppColors.lightPrimary, 'Installation',""", r"""AppColors.lightPrimary, AppStrings.installation,"""),
    (r"""AppColors.lightPurple, 'Support',""", r"""AppColors.lightPurple, AppStrings.support,"""),
    (r"""_error = 'Could not load your home. Pull down to retry.'""", r"""_error = AppStrings.homeLoadError"""),

    # ---- devices_tab ----
    (r"""'$city · $total registered'""", r"""AppStrings.citySummary(city, total)"""),
    (r"""'${e.product} · Pincode ${e.pincode}'""", r"""AppStrings.productPincode(e.product, e.pincode)"""),
    (r"""'Requesting service for ${results.length} appliance${results.length == 1 ? '' : 's'}…'""",
     r"""AppStrings.requestingService(results.length)"""),
    (r"""'${results.length} RESULT${results.length == 1 ? '' : 'S'} FOR "${_query.trim()}"'""",
     r"""AppStrings.resultsFor(results.length, _query.trim())"""),
    (r"""'Book service for all ${results.length}'""", r"""AppStrings.bookServiceForAll(results.length)"""),
    (r"""'Warranty expired · $days d ago'""", r"""AppStrings.warrantyExpiredAgo(days)"""),
    (r"""'Warranty expiring · $daysLeft days'""", r"""AppStrings.warrantyExpiring(daysLeft)"""),
    (r"""'Warranty active · $years${daysLeft >= 365 ? 'yr' : ' yrs'}'""",
     r"""AppStrings.warrantyActiveFor(years, daysLeft >= 365 ? 'yr' : ' yrs')"""),
    (r"""'"$q" is not registered in your home yet.'""", r"""AppStrings.notRegisteredYet(q)"""),
    (r"""'Scan and add $q'""", r"""AppStrings.scanAndAdd(q)"""),
    (r"""'${e.roomName} · Purchased ${e.purchasedYear}'""", r"""AppStrings.roomPurchased(e.roomName, e.purchasedYear)"""),
    (r"""'Expires in $days days'""", r"""AppStrings.expiresInDays(days)"""),
    (r"""'$days days ago'""", r"""AppStrings.daysAgo(days)"""),
    (r"""'${e.product} will be removed from ${e.roomName}.'""", r"""AppStrings.removeApplianceContent(e.product, e.roomName)"""),
    (r"""'${e.product} removed ✅'""", r"""AppStrings.applianceRemoved(e.product)"""),
    (r"""'All ${all.length}'""", r"""AppStrings.pillAll(all.length)"""),
    (r"""'Attention $attentionCount'""", r"""AppStrings.pillAttention(attentionCount)"""),
    (r"""'Warranty $warrantyOk'""", r"""AppStrings.pillWarranty(warrantyOk)"""),
    (r"""badgeText = 'Unregistered'""", r"""badgeText = AppStrings.unregistered"""),

    # ---- scan_tab ----
    (r"""'Scan failed (${response.statusCode}). Try again.'""", r"""AppStrings.scanFailed(response.statusCode)"""),
    (r"""'Updated: ${_effectiveBrand ?? "Unbranded"} • ${_resultLabel ?? "—"}'""",
     r"""AppStrings.updatedBrandProduct(_effectiveBrand ?? AppStrings.unbranded, _resultLabel ?? '—')"""),
    (r"""'$_resultLabel (${_effectiveBrand ?? "Unbranded"}) saved ✅'""",
     r"""AppStrings.applianceSaved(_resultLabel ?? '', _effectiveBrand ?? AppStrings.unbranded)"""),
    (r"""'Cancel ($_reviewCountdown)'""", r"""AppStrings.cancelWithCount(_reviewCountdown)"""),
    (r"""'Page ${_servicePage + 1} of $_serviceTotalPages'""", r"""AppStrings.pageOf(_servicePage + 1, _serviceTotalPages)"""),
    (r"""_aiThinking ? 'Checking...' :""", r"""_aiThinking ? AppStrings.checking :"""),
    (r"""_effectiveBrand != null ? 'Edit' : 'Add'""", r"""_effectiveBrand != null ? AppStrings.edit : AppStrings.add"""),

    # ---- service_tab ----
    (r"""'Ticket #$ticketId'""", r"""AppStrings.ticketNumber(ticketId)"""),
    (r"""'Could not load tickets (${response.statusCode}).'""", r"""AppStrings.couldNotLoadTicketsCode(response.statusCode)"""),
    (r"""'Could not cancel ticket (${response.statusCode}).'""", r"""AppStrings.couldNotCancelTicket(response.statusCode)"""),
    (r"""'$city · ${_tickets.length} ticket${_tickets.length == 1 ? '' : 's'}'""",
     r"""AppStrings.ticketsSummary(city, _tickets.length)"""),
    (r"""'Near pincode ${widget.pincode}'""", r"""AppStrings.nearPincode(widget.pincode)"""),
    (r"""'$count available now'""", r"""AppStrings.availableNow(count)"""),
    (r"""'GST (${bill.gstPercent % 1 == 0 ? bill.gstPercent.toStringAsFixed(0) : bill.gstPercent}%)'""",
     r"""AppStrings.gstLabel((bill.gstPercent % 1 == 0 ? bill.gstPercent.toStringAsFixed(0) : bill.gstPercent).toString())"""),
    (r"""'${bill.warrantyDays} days warranty on this service'""", r"""AppStrings.warrantyOnService(bill.warrantyDays)"""),

    # ---- profile_tab ----
    (r"""'$name (You)'""", r"""AppStrings.youSuffix(name)"""),
    (r"""isMe ? 'Owner' : 'Member'""", r"""isMe ? AppStrings.owner : AppStrings.member"""),
    (r"""'$name removed ✅'""", r"""AppStrings.memberRemoved(name)"""),
    (r"""'$name will lose access to this home.'""", r"""AppStrings.memberLosesAccess(name)"""),
    (r"""'Since ${_monthYear(widget.memberSince!)}'""", r"""AppStrings.sinceDate(_monthYear(widget.memberSince!))"""),
    (r"""return '$active active · $expired expired';""", r"""return AppStrings.warrantyVaultSubtitle(active, expired);"""),
    (r"""'${plan.slotsUsed} of ${plan.slotsTotal} appliance slots used · Renews ${_monthYear(plan.renewsOn)}'""",
     r"""AppStrings.slotsUsed(plan.slotsUsed, plan.slotsTotal, _monthYear(plan.renewsOn))"""),
    (r"""'$daysLeft days remaining'""", r"""AppStrings.daysRemaining(daysLeft)"""),
    (r"""'Upgrade to ${plan.upgradeToSlots} ↗'""", r"""AppStrings.upgradeTo(plan.upgradeToSlots)"""),
    (r"""'Upgrade your AMC to cover up to ${plan.upgradeToSlots} appliances.'""", r"""AppStrings.upgradePlanDesc(plan.upgradeToSlots)"""),
    (r"""'$deviceCount devices · ${isSelected ? 'AMC active' : 'No AMC'}'""", r"""AppStrings.devicesAmc(deviceCount, isSelected)"""),
    (r"""'Home ${entry.key + 1}'""", r"""AppStrings.homeN(entry.key + 1)"""),
    (r"""_heroChip(Icons.verified_rounded, 'Verified')""", r"""_heroChip(Icons.verified_rounded, AppStrings.verified)"""),
    (r"""path: 'support@zhini.co.in'""", r"""path: AppStrings.supportEmail"""),
]

# multi-line / regex based replacements
REGEX_SUBS = [
    # scan_tab: "Warranty: xxx (Active)"
    (
        r"""'Warranty: \$\{_detectedWarranty \?\? _manualWarranty\}'\s*'\$\{_isUnderWarrantyNow \? " \(Active\)" : ""\}'""",
        "AppStrings.warrantyLine((_detectedWarranty ?? _manualWarranty)!, _isUnderWarrantyNow)",
    ),
    # service_tab: quick reasons list
    (r"""const quickReasons = \[.*?\];""", "const quickReasons = AppStrings.quickReasonList;"),
    # profile_tab: referral message
    (r"""const referralMessage =\s*"Hey!.*?";""", "const referralMessage = AppStrings.referralMessage;"),
]

# ---------------------------------------------------------------------
# 3. Process the files
# ---------------------------------------------------------------------
IMPORT_LINE = "import 'constants/app_strings.dart';"
total_changes = 0

for fname in TARGETS:
    path = LIB / fname
    if not path.exists():
        print(f"SKIP  {fname} (file illa)")
        continue

    text = path.read_text(encoding="utf-8")
    original = text

    for old, new in DYNAMIC:
        text = text.replace(old, new)

    for rx, new in REGEX_SUBS:
        text = re.sub(rx, new, text, flags=re.S)

    for token, name in token_to_name.items():
        raw = token[1:-1]
        single_word = not re.search(r"\s", raw)
        if single_word:
            rx = r"((?:" + CONTEXTS + r")\s*)" + re.escape(token)
            text = re.sub(rx, lambda m, n=name: m.group(1) + "AppStrings." + n, text)
        else:
            text = text.replace(token, "AppStrings." + name)

    if "AppStrings." in text and IMPORT_LINE not in text:
        text = text.replace(
            "import 'package:flutter/material.dart';",
            "import 'package:flutter/material.dart';\n" + IMPORT_LINE,
            1,
        )

    if text != original:
        path.write_text(text, encoding="utf-8")
        count = text.count("AppStrings.") - original.count("AppStrings.")
        total_changes += count
        print(f"DONE  {fname}: {count} replacements")
    else:
        print(f"SAME  {fname}: maaralai")

print(f"\nTotal replacements: {total_changes}")

# ---------------------------------------------------------------------
# 4. Report what is still hardcoded
# ---------------------------------------------------------------------
print("\n--- Innum hardcoded irukkura idangal (manual ah paarunga) ---")
leftover = re.compile(r"""(Text\(\s*(const\s+)?['"]|hint(Text)?:\s*['"]|_snack\(\s*['"]|_showSnack\(\s*['"])""")
for fname in TARGETS:
    path = LIB / fname
    if not path.exists():
        continue
    for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if leftover.search(line) and "AppStrings." not in line:
            print(f"{fname}:{i}: {line.strip()[:110]}")