// lib/constants/app_strings.dart
//
// ONE place for every word shown in the app.
// Static const  -> usable inside `const Text(AppStrings.x)`.
// Static method -> for text with variables (name, count, date...).

class AppStrings {
  AppStrings._();

  // ===================================================================
  // COMMON
  // ===================================================================
  static const String appName = 'ZHINI';
  static const String retry = 'Retry';
  static const String cancel = 'Cancel';
  static const String save = 'Save';
  static const String close = 'Close';
  static const String edit = 'Edit';
  static const String add = 'Add';
  static const String change = 'Change';
  static const String ok = 'OK';
  static const String gotIt = 'Got it';
  static const String remove = 'Remove';
  static const String loading = 'Loading...';
  static const String previous = 'Previous';
  static const String next = 'Next';
  static const String networkError = 'Network error. Try again.';
  static const String networkErrorPleaseRetry = 'Network error. Please try again.';
  static const String sessionExpired = 'Session expired. Please login again.';
  static const String notAvailable = 'Not available';
  static const String noProvidersFound = 'No service providers found nearby.';
  static const String appliance = 'Appliance';
  static const String unbranded = 'Unbranded';
  static const String couldNotOpenMaps = 'Could not open maps.';
  static const String noPhoneAvailable = 'No phone number available.';
  static const String couldNotStartCall = 'Could not start call.';
  static String homeN(int n) => 'Home $n';

  // ===================================================================
  // SERVICE CATEGORIES (Home tab + Service tab)
  // ===================================================================
  static const String electrician = 'Electrician';
  static const String plumber = 'Plumber';
  static const String acService = 'AC Service';
  static const String carpenter = 'Carpenter';
  static const String painter = 'Painter';
  static const String pestControl = 'Pest Control';

  // ===================================================================
  // HOME TAB
  // ===================================================================
  static const String searchHere = 'Search here...';
  static const String buildings = 'Buildings';
  static const String select = 'Select';
  static const String addNewBuilding = 'Add new building';
  static String devicesCount(int n) => 'Devices ($n)';
  static const String viewAll = 'View all';
  static const String allDevices = 'All devices';

  static const String statAppliances = 'Appliances';
  static const String statActiveWarranties = 'Active Warranties';
  static const String statAttention = 'Attention';

  static const String noAppliancesYet = 'No appliances yet';
  static const String tapAddDeviceBelow = 'Tap + Add Device below to add one.';
  static const String brandNotAdded = 'Brand not added';
  static const String noWarrantyInfo = 'No warranty info';
  static const String warrantyActive = 'Warranty Active';
  static const String warrantyExpired = 'Warranty Expired';
  static String validTill(String date) => 'Valid till $date';
  static String expiredOn(String date) => 'Expired on $date';

  static const String addApplianceManually = 'Add appliance manually';
  static const String addApplianceTitle = 'Add Appliance';
  static const String scan = 'Scan';
  static const String productNameHintExample = 'Product name (e.g. Refrigerator)';
  static const String brandOptionalHint = 'Brand (optional)';
  static const String warrantyOptionalHint = 'Warranty (e.g. 2 Years, optional)';
  static const String addApplianceButton = 'Add appliance';

  static const String servicesNearYou = 'Services near you';
  static String nearbyCount(int n) => '$n nearby';
  static const String installation = 'Installation';
  static const String installationDesc = 'Get expert setup at your home';
  static const String support = 'Support';
  static const String supportDesc = 'Quick help, anytime';

  static const String setUpYourHome = 'Set up your home';
  static const String setUpYourHomeDesc =
      'Add your address to start tracking appliances, warranties, and get matched with nearby services.';
  static const String register = 'Register';
  static String defaultDevices(int n) => 'Default devices ($n)';
  static const String defaultDevicesNote = 'These will move into your home once you register.';
  static String moreCount(int n) => '+$n more';

  static const String homeLoadError = 'Could not load your home. Pull down to retry.';
  static const String couldNotCreateHome = 'Could not create the new home. Try again.';
  static const String homeAdded = 'Home added ✅';
  static const String signInAgainToAddHome = 'Please sign in again to add a home.';
  static const String addressUpdated = 'Address updated successfully ✅';
  static const String addressUpdateFailed = 'Failed to update address';
  static const String couldNotSetupHome = 'Could not set up your home. Try again.';
  static String applianceAdded(String product) => '$product added ✅';
  static const String couldNotAddAppliance = 'Could not add appliance. Try again.';

  // ===================================================================
  // DEVICES TAB
  // ===================================================================
  static const String myDevices = 'My Devices';
  static String citySummary(String city, int total) => '$city · $total registered';
  static const String scanNew = 'Scan new';
  static const String searchApplianceHint = 'Search appliances, brand, room…';

  // Tab / pill DISPLAY labels (keep the internal keys 'All', 'Warranty'... as they are!)
  static const String tabAll = 'All';
  static const String tabWarranty = 'Warranty';
  static const String tabAttention = 'Attention';
  static const String tabExpired = 'Expired';
  static const String tabService = 'Service';
  static String pillAll(int n) => 'All $n';
  static String pillAttention(int n) => 'Attention $n';
  static String pillWarranty(int n) => 'Warranty $n';

  static const String recentSearches = 'RECENT SEARCHES';
  static const String browseByCategory = 'BROWSE BY CATEGORY';
  static const String quickFilters = 'QUICK FILTERS';
  static const String filterExpiredWarranty = 'Expired warranty';
  static const String filterServiceDue = 'Service due';
  static const String filterByRoom = 'By room';
  static const String filterHealthy = 'Healthy';
  static const String filterByRoomTitle = 'Filter by room';

  static const String catAc = 'AC';
  static const String catFridge = 'Fridge';
  static const String catWashingMachine = 'Wt. Machine';
  static const String catTv = 'TV';
  static const String catFan = 'Fan';

  static String resultsFor(int n, String query) =>
      '$n RESULT${n == 1 ? '' : 'S'} FOR "$query"';
  static String bookServiceForAll(int n) => 'Book service for all $n';
  static String requestingService(int n) =>
      'Requesting service for $n appliance${n == 1 ? '' : 's'}…';

  static const String unregistered = 'Unregistered';
  static String warrantyExpiredAgo(int days) => 'Warranty expired · $days d ago';
  static String warrantyExpiring(int days) => 'Warranty expiring · $days days';
  static String warrantyActiveFor(String years, String unit) =>
      'Warranty active · $years$unit';

  static const String noApplianceFound = 'No appliance found';
  static String notRegisteredYet(String q) => '"$q" is not registered in your home yet.';
  static const String tryDifferentSearch = 'Try a different search or filter.';
  static String scanAndAdd(String q) => 'Scan and add $q';
  static const String scanAndAddAppliance = 'Scan and add appliance';
  static const String orTrySearchingFor = 'Or try searching for:';
  static const String byBrand = 'By brand';

  static const String needsAttention = '⚠ NEEDS ATTENTION';
  static const String serviceDueHeader = '🔧 SERVICE DUE';
  static const String healthyDevices = '✓ HEALTHY DEVICES';
  static const String noDevicesInFilter = 'No devices in this filter';

  static const String warrantyExpiredLabel = 'Warranty expired';
  static String expiresInDays(int d) => 'Expires in $d days';
  static String daysAgo(int d) => '$d days ago';
  static const String serviceDueLabel = 'Service due';
  static const String warrantyActiveLabel = 'Warranty active';
  static const String noWarrantyData = 'No warranty data';
  static String roomPurchased(String room, String year) => '$room · Purchased $year';

  static const String findService = 'Find service';
  static const String authorizedServiceCenters = 'Authorized service centers';
  static const String localRepairProviders = 'Local repair providers';
  static String productPincode(String product, String pin) => '$product · Pincode $pin';

  static const String editAppliance = 'Edit Appliance';
  static const String productNameHint = 'Product name';
  static const String brandHint = 'Brand';
  static const String noDeviceIdCannotEdit = 'This item has no deviceId, cannot edit.';
  static const String applianceUpdated = 'Appliance updated ✅';
  static const String updateFailed = 'Update failed';
  static const String removeApplianceQ = 'Remove appliance?';
  static String removeApplianceContent(String product, String room) =>
      '$product will be removed from $room.';
  static String applianceRemoved(String product) => '$product removed ✅';
  static const String couldNotRemoveAppliance = 'Could not remove appliance.';

  // ===================================================================
  // SCAN TAB
  // ===================================================================
  static const String couldNotOpenCamera = 'Could not open camera.';
  static const String scanAppliance = 'Scan Appliance';
  static const String scanHint = 'Point at the appliance, then tap the button.';
  static const String capturedProduct = 'Captured product';
  static String cancelWithCount(int n) => 'Cancel ($n)';
  static const String proceed = 'Proceed';

  static String scanFailed(int code) => 'Scan failed ($code). Try again.';
  static const String couldNotIdentify = 'Could not identify this. Try again with better lighting.';
  static const String noApplianceFoundPointCamera =
      'No appliance found. Point the camera at an appliance.';
  static const String networkErrorWhileScanning = 'Network error while scanning. Try again.';
  static String updatedBrandProduct(String brand, String product) =>
      'Updated: $brand • $product';

  static const String warrantyCardUploaded = 'Warranty card uploaded ✅';
  static const String couldNotUploadWarrantyCard = 'Could not upload warranty card.';
  static const String uploadFailed = 'Upload failed. Try again.';
  static const String networkErrorWhileUploading = 'Network error while uploading.';

  static const String warranty = 'Warranty';
  static const String warrantyDialogHint = 'e.g. 2 Years or 12/2027';
  static const String brand = 'Brand';
  static const String brandDialogHint = 'e.g. LG, Samsung, Godrej';

  static String applianceSaved(String product, String brand) => '$product ($brand) saved ✅';
  static const String submitFailed = 'Submit failed. Try again.';

  static const String productDetected = 'Product Detected';
  static const String askZhini = 'Ask ZHINI';
  static const String checking = 'Checking...';
  static String warrantyLine(String value, bool active) =>
      'Warranty: $value${active ? " (Active)" : ""}';
  static const String warrantyNotAddedYet = 'Warranty not added yet';
  static const String addManual = 'Add manual';
  static const String uploadWarrantyCard = 'Upload warranty card';
  static const String warrantyCardAdded = 'Warranty card added';
  static const String authorizedCentersByRating = 'Authorized Service Centers (by rating)';
  static const String recommendedCentersByRating = 'Recommended Service Centers (by rating)';
  static String pageOf(int page, int total) => 'Page $page of $total';
  static const String brandNotIdentified =
      'Brand not identified — tap "Add" above to enter it, or "Ask ZHINI" to check again.';
  static const String noAuthorizedCentersFound = 'No authorized service centers found nearby.';
  static const String scanAnotherAppliance = 'Scan Another Appliance';

  // ===================================================================
  // SERVICE TAB
  // ===================================================================
  static const String service = 'Service';
  static String ticketsSummary(String city, int n) =>
      '$city · $n ticket${n == 1 ? '' : 's'}';

  // Filter DISPLAY labels (keep keys 'all', 'open'... as they are!)
  static const String filterAll = 'All';
  static const String filterOpen = 'Open';
  static const String filterInProgress = 'In Progress';
  static const String filterCompleted = 'Completed';
  static const String filterCancelled = 'Cancelled';

  static const String couldNotLoadTickets = 'Could not load tickets.';
  static String couldNotLoadTicketsCode(int code) => 'Could not load tickets ($code).';
  static const String networkErrorPullRetry = 'Network error. Pull down to retry.';
  static const String ticketCancelledOk = 'Ticket cancelled successfully.';
  static String couldNotCancelTicket(int code) => 'Could not cancel ticket ($code).';

  static const String statusUnknown = 'Status unknown';
  static const String serviceRequest = 'Service request';
  static String ticketNumber(String id) => 'Ticket #$id';

  static const String invoice = 'Invoice';
  static const String noItemizedBreakdown = 'No itemized breakdown available.';
  static const String labourCharge = 'Labour Charge';
  static const String subtotal = 'Subtotal';
  static String gstLabel(String percent) => 'GST ($percent%)';
  static const String total = 'Total';
  static String warrantyOnService(dynamic days) => '$days days warranty on this service';

  static const String cancelThisTicket = 'Cancel this ticket?';
  static const String quickReasons = 'Quick reasons';
  static const List<String> quickReasonList = [
    'Found a local technician',
    'Changed my mind',
    'Price too high',
    'Taking too long',
  ];
  static const String orTypeYourOwnReason = 'Or type your own reason';
  static const String tellUsWhy = "Tell us why you're cancelling...";
  static const String technicianWillBeNotified =
      'Your assigned technician will be notified once cancelled.';
  static const String keepTicket = 'Keep ticket';
  static const String confirmCancel = 'Confirm cancel';
  static const String pleaseAddReason = 'Please add a reason to cancel.';

  static const String noTicketsYet =
      'No tickets yet.\nBook a repair from any appliance to see it here.';
  static const String noTicketsMatchFilter = 'No tickets match this filter.';
  static const String quickBook = '⚡ QUICK BOOK';
  static String nearPincode(String pin) => 'Near pincode $pin';
  static const String nearYourLocation = 'Near your current location';
  static String availableNow(int n) => '$n available now';

  // ===================================================================
  // PROFILE TAB
  // ===================================================================
  static const String myProfile = 'My Profile';
  static const String addYourName = 'Add your name';
  static const String verified = 'Verified';
  static String sinceDate(String d) => 'Since $d';

  static const String editProfile = 'Edit Profile';
  static const String fullName = 'Full name';
  static const String enterName = 'Enter a name.';
  static const String nameSavedSyncLater = 'Name saved. It will sync once you register a home.';
  static const String nameUpdated = 'Name updated successfully ✅';
  static const String nameUpdateFailed = 'Failed to update name';

  static const String editAddress = 'Edit Address';
  static const String address = 'Address';
  static const String pincode = 'Pincode';
  static const String enterAddress = 'Enter the address.';

  static const String homeRegistered = 'Home registered successfully ✅';
  static const String homeRegisterFailed = 'Failed to register home';

  static const String referNeighbour = 'Refer a Neighbour';
  static const String referNeighbourDesc =
      "Share ZHINI with a neighbour — they'll be able to track their own home's appliances too.";
  static const String copyLink = 'Copy Link';
  static const String referralCopied = 'Referral message copied — paste it anywhere ✅';
  static const String referralMessage =
      "Hey! I've been using ZHINI to track all my home appliances, warranties, and find repair services in one place. Try it out 👉 https://play.google.com/store/apps/details?id=com.zhini.mobile";

  static const String logOutQ = 'Log out?';
  static const String logOutContent =
      "You'll need to verify your mobile number when you sign in again.";
  static const String logOut = 'Log out';
  static const String signOut = 'Sign out';
  static const String couldNotRefresh = 'Could not refresh. Try again.';

  static const String addHome = 'Add home';
  static const String addAnotherHome = 'Add another home';
  static const String appearance = 'APPEARANCE';
  static const String accountActions = 'ACCOUNT ACTIONS';

  static const String household = 'HOUSEHOLD';
  static const String noMembersYet = 'No members added yet.';
  static const String member = 'Member';
  static const String owner = 'Owner';
  static String youSuffix(String name) => '$name (You)';
  static const String addMember = 'Add Member';
  static const String addMemberDesc =
      'They will be able to see and manage all appliances in this home.';
  static const String pickFromContacts = 'Pick from Contacts';
  static const String noContactSelected = 'No contact selected yet.';
  static const String contactsPermissionDenied = 'Contacts permission denied.';
  static const String noValid10Digit = 'This contact has no valid 10-digit number.';
  static const String noHomeSelected = 'No home selected. Please select a home first.';
  static const String removeMemberQ = 'Remove member?';
  static String memberLosesAccess(String name) => '$name will lose access to this home.';
  static String memberRemoved(String name) => '$name removed ✅';

  static const String statDevicesRegistered = 'Devices\nregistered';
  static const String statServiceRequests = 'Service\nrequests';
  static const String statSavedViaWarranty = 'Saved via\nwarranty';

  static const String myProtectionPlan = 'MY PROTECTION PLAN';
  static const String noActiveProtectionPlan = 'No active protection plan';
  static const String coverAllAppliancesAmc = 'Cover all your appliances under one AMC plan.';
  static const String explore = 'Explore';
  static const String protectionPlans = 'Protection plans';
  static const String protectionPlansDesc =
      'Browse AMC plans that cover repairs and servicing for your appliances.';
  static const String activeBadge = 'ACTIVE';
  static String slotsUsed(int used, int total, String renews) =>
      '$used of $total appliance slots used · Renews $renews';
  static String daysRemaining(int n) => '$n days remaining';
  static String upgradeTo(int n) => 'Upgrade to $n ↗';
  static const String upgradePlan = 'Upgrade plan';
  static String upgradePlanDesc(int n) => 'Upgrade your AMC to cover up to $n appliances.';

  static const String myHomes = 'MY HOMES';
  static const String noHomesYet = 'No homes yet.';
  static const String primaryBadge = 'PRIMARY';
  static String devicesAmc(int n, bool amc) =>
      '$n devices · ${amc ? 'AMC active' : 'No AMC'}';

  static const String myStuff = 'MY STUFF';
  static const String warrantyVault = 'Warranty vault';
  static const String warrantyVaultDesc =
      'A full list of active and expired warranties across all your homes will show up here.';
  static String warrantyVaultSubtitle(int active, int expired) =>
      '$active active · $expired expired';
  static const String documentLocker = 'Document locker';
  static const String documentLockerSub = 'Bills · Manuals · Photos';
  static const String documentLockerChip = '14 files';
  static const String documentLockerDesc =
      'Upload and store bills, manuals and photos against each appliance.';
  static const String reminders = 'Reminders';
  static const String remindersSub = 'Warranty · Service · AMC';
  static const String remindersDesc =
      'Get notified before warranties expire or a service is due.';

  static const String rewardsBilling = 'REWARDS & BILLING';
  static const String referNeighbourRow = 'Refer a neighbour';
  static const String referNeighbourSub = '2 referrals · ₹200 earned';
  static const String referNeighbourChip = 'Earn ₹100';
  static const String paymentsBilling = 'Payments and billing';
  static const String paymentsBillingSub = 'UPI · Cards · History';
  static const String paymentsBillingDesc =
      'Manage saved payment methods and view your billing history.';

  static const String supportSection = 'SUPPORT';
  static const String preferences = 'Preferences';
  static const String preferencesSub = 'Language · Notifications · Theme';
  static const String preferencesDesc = 'App language, notification and theme settings.';
  static const String helpSupport = 'Help and support';
  static const String helpSupportSub = 'FAQ · Chat · Call ZHINI';
  static const String helpSupportDesc =
      'Reach ZHINI support via chat, call, or browse the FAQ.';
  static const String aboutZhini = 'About ZHINI';
  static const String aboutZhiniSub = 'v1.0.0 · Built by two kids';
  static const String aboutZhiniDesc =
      "ZHINI v1.0.0 — your home's appliance and warranty companion.";

  static const String profileFooter = 'Your data is never sold · DPDP compliant · v1.0.0';
  static const String poweredBy = 'powered by Atom8';
  static const String supportEmail = 'support@zhini.co.in';
  static const String supportEmailSubject = 'ZHINI App Support';
  static const String couldNotOpenMail = 'Could not open mail app.';
}