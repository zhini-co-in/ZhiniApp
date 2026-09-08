class ApiConfig {
  //static const String baseUrl = 'https://zhini.atom8itsolutions.com'; // unnoda machine IP, localhost illa (phone-la run panna)
   static const String baseUrl = 'https://crucial-purifier-canopener.ngrok-free.dev';

  static const String productSubmitUrl = '$baseUrl/product/submit';
  static const String submissionSearchUrl = '$baseUrl/product/search';
  static const String serviceLocatorUrl = '$baseUrl/service/service';
  static const String memberAddUrl = '$baseUrl/product/member'; // 👈 ADDED

  static String stripCountryCode(String phone) => phone.replaceFirst('+91', '').trim();
  static String get aiAssistUrl => '$baseUrl/product/ai';
  static const String homeServicesUrl = '$baseUrl/service/home-services';
  // existing pattern la irukura maari, homeId ah path la pass pannum
  static String homeUpdateUrl(String homeId) {
  if (homeId.isEmpty) {
    throw Exception('Home ID cannot be empty');
  }
  return '$baseUrl/product/update/$homeId';
}
static String get mediaUploadUrl => '$baseUrl/product/submit'; // 👈 adjust path to match your actual route
static String memberDeleteUrl(String homeId) => '$baseUrl/product/delete-member/$homeId';
  static String productDeleteUrl(String homeId) => '$baseUrl/product/delete-product/$homeId';
  static String get createServiceProviderUrl => '$baseUrl/service/create-provider';
  static String getServiceProviderUrl(String mobileNumber) =>
    '$baseUrl/service/provider?mobile=$mobileNumber';
    // constants/api_config.dart
static String get updateEntityUrl => '$baseUrl/product/update';
static const String nearbyServiceUrl = '$baseUrl/service/service';
static const String createServiceTicketUrl = '$baseUrl/service/create-ticket';
static String get providerTicketsUrl => '$baseUrl/service/provider-tickets';
    static String get ticketRespondUrl => '$baseUrl/service/update-status';
    static String customerBillingUrl(String phone) =>
    '$baseUrl/service/billing/$phone';
    static String cancelTicketUrl() => '$baseUrl/service/cancel-ticket';
    static String get createHomeUrl => '$baseUrl/product/home'; // adjust path if different on your backend
    static String deleteRoomUrl(String homeId) => '$baseUrl/product/delete-room/$homeId';

}