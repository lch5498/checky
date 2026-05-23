import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'api_config.dart';

class ApiClient {
  ApiClient({String? baseUrl, Duration timeout = const Duration(seconds: 8)})
    : _baseUrl = Uri.parse(baseUrl ?? ApiConfig.baseUrl),
      _timeout = timeout;

  final Uri _baseUrl;
  final Duration _timeout;

  Future<Map<String, Object?>> getHealth() {
    return _requestJson('GET', '/api/health');
  }

  Future<AuthResponse> loginWithKakaoAccessToken(
    String accessToken, {
    String? nickname,
  }) async {
    final body = <String, Object?>{'accessToken': accessToken};

    if (nickname != null) {
      body['nickname'] = nickname;
    }

    final json = await _requestJson(
      'POST',
      '/api/mobile/auth/kakao',
      body: body,
    );

    return AuthResponse.fromJson(json);
  }

  Future<Map<String, Object?>> getMe(String sessionToken) {
    return _requestJson(
      'GET',
      '/api/mobile/auth/me',
      bearerToken: sessionToken,
    );
  }

  Future<AppUser> updateMyProfile(
    String sessionToken, {
    required String nickname,
  }) async {
    final json = await _requestJson(
      'PATCH',
      '/api/mobile/auth/me',
      bearerToken: sessionToken,
      body: {'nickname': nickname},
    );

    return AppUser.fromJson(json['user'] as Map<String, Object?>);
  }

  Future<List<FamilySummary>> listFamilies(String sessionToken) async {
    final json = await _requestJson(
      'GET',
      '/api/mobile/families',
      bearerToken: sessionToken,
    );
    final families = json['families'] as List<Object?>;

    return families
        .map((family) => FamilySummary.fromJson(family as Map<String, Object?>))
        .toList();
  }

  Future<AppFamily> createFamily(
    String sessionToken, {
    required String name,
  }) async {
    final json = await _requestJson(
      'POST',
      '/api/mobile/families',
      bearerToken: sessionToken,
      body: {'name': name},
    );

    return AppFamily.fromJson(json['family'] as Map<String, Object?>);
  }

  Future<FamilyDetail> getFamily(
    String sessionToken, {
    required String familyId,
  }) async {
    final json = await _requestJson(
      'GET',
      '/api/mobile/families/$familyId',
      bearerToken: sessionToken,
    );

    return FamilyDetail.fromJson(json);
  }

  Future<AppFamily> updateFamily(
    String sessionToken, {
    required String familyId,
    required String name,
  }) async {
    final json = await _requestJson(
      'PATCH',
      '/api/mobile/families/$familyId',
      bearerToken: sessionToken,
      body: {'name': name},
    );

    return AppFamily.fromJson(json['family'] as Map<String, Object?>);
  }

  Future<void> deleteFamily(
    String sessionToken, {
    required String familyId,
  }) async {
    await _requestJson(
      'DELETE',
      '/api/mobile/families/$familyId',
      bearerToken: sessionToken,
    );
  }

  Future<FamilyInvitation> createFamilyInvitation(
    String sessionToken, {
    required String familyId,
    required String role,
  }) async {
    final json = await _requestJson(
      'POST',
      '/api/mobile/families/$familyId/invitations',
      bearerToken: sessionToken,
      body: {'role': role},
    );

    return FamilyInvitation.fromJson(
      json['invitation'] as Map<String, Object?>,
    );
  }

  Future<void> deleteFamilyMember(
    String sessionToken, {
    required String familyId,
    required String memberId,
  }) async {
    await _requestJson(
      'DELETE',
      '/api/mobile/families/$familyId/members/$memberId',
      bearerToken: sessionToken,
    );
  }

  Future<FamilyDetail> acceptFamilyInvitation(
    String sessionToken, {
    required String inviteToken,
  }) async {
    final json = await _requestJson(
      'POST',
      '/api/mobile/family-invitations/$inviteToken',
      bearerToken: sessionToken,
    );

    return FamilyDetail.fromJson(json);
  }

  Future<ParkingDashboard> getParkingDashboard(
    String sessionToken, {
    required String familyId,
  }) async {
    final json = await _requestJson(
      'GET',
      '/api/mobile/families/$familyId/parking',
      bearerToken: sessionToken,
    );

    return ParkingDashboard.fromJson(json);
  }

  Future<Vehicle> createVehicle(
    String sessionToken, {
    required String familyId,
    required String nickname,
    required String plateNumber,
  }) async {
    final json = await _requestJson(
      'POST',
      '/api/mobile/families/$familyId/parking/vehicles',
      bearerToken: sessionToken,
      body: {'nickname': nickname, 'plateNumber': plateNumber},
    );

    return Vehicle.fromJson(json['vehicle'] as Map<String, Object?>);
  }

  Future<Vehicle> updateVehicle(
    String sessionToken, {
    required String familyId,
    required String vehicleId,
    required String nickname,
    required String plateNumber,
  }) async {
    final json = await _requestJson(
      'PATCH',
      '/api/mobile/families/$familyId/parking/vehicles/$vehicleId',
      bearerToken: sessionToken,
      body: {'nickname': nickname, 'plateNumber': plateNumber},
    );

    return Vehicle.fromJson(json['vehicle'] as Map<String, Object?>);
  }

  Future<void> deleteVehicle(
    String sessionToken, {
    required String familyId,
    required String vehicleId,
  }) async {
    await _requestJson(
      'DELETE',
      '/api/mobile/families/$familyId/parking/vehicles/$vehicleId',
      bearerToken: sessionToken,
    );
  }

  Future<ParkingLocationPreset> createParkingLocationPreset(
    String sessionToken, {
    required String familyId,
    required String name,
  }) async {
    final json = await _requestJson(
      'POST',
      '/api/mobile/families/$familyId/parking/presets',
      bearerToken: sessionToken,
      body: {'name': name},
    );

    return ParkingLocationPreset.fromJson(
      json['preset'] as Map<String, Object?>,
    );
  }

  Future<ParkingLocationPreset> updateParkingLocationPreset(
    String sessionToken, {
    required String familyId,
    required String presetId,
    required String name,
  }) async {
    final json = await _requestJson(
      'PATCH',
      '/api/mobile/families/$familyId/parking/presets/$presetId',
      bearerToken: sessionToken,
      body: {'name': name},
    );

    return ParkingLocationPreset.fromJson(
      json['preset'] as Map<String, Object?>,
    );
  }

  Future<void> deleteParkingLocationPreset(
    String sessionToken, {
    required String familyId,
    required String presetId,
  }) async {
    await _requestJson(
      'DELETE',
      '/api/mobile/families/$familyId/parking/presets/$presetId',
      bearerToken: sessionToken,
    );
  }

  Future<ParkingRecord> createParkingRecord(
    String sessionToken, {
    required String familyId,
    required String vehicleId,
    String? presetId,
    required String locationText,
  }) async {
    final body = <String, Object?>{
      'vehicleId': vehicleId,
      'locationText': locationText,
    };

    if (presetId != null) {
      body['presetId'] = presetId;
    }

    final json = await _requestJson(
      'POST',
      '/api/mobile/families/$familyId/parking/records',
      bearerToken: sessionToken,
      body: body,
    );

    return ParkingRecord.fromJson(json['record'] as Map<String, Object?>);
  }

  Future<ScheduleDashboard> getScheduleDashboard(
    String sessionToken, {
    required String familyId,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    final path = Uri(
      path: '/api/mobile/families/$familyId/schedules',
      queryParameters: {
        'rangeStart': rangeStart.toUtc().toIso8601String(),
        'rangeEnd': rangeEnd.toUtc().toIso8601String(),
      },
    ).toString();
    final json = await _requestJson('GET', path, bearerToken: sessionToken);

    return ScheduleDashboard.fromJson(json);
  }

  Future<AppSchedule> createSchedule(
    String sessionToken, {
    required String familyId,
    required String familyMemberId,
    required String title,
    String? content,
    required DateTime startsAt,
    required DateTime endsAt,
    DateTime? vehicleBoardingAt,
    DateTime? vehicleDropoffAt,
  }) async {
    final json = await _requestJson(
      'POST',
      '/api/mobile/families/$familyId/schedules',
      bearerToken: sessionToken,
      body: _scheduleBody(
        familyMemberId: familyMemberId,
        title: title,
        content: content,
        startsAt: startsAt,
        endsAt: endsAt,
        vehicleBoardingAt: vehicleBoardingAt,
        vehicleDropoffAt: vehicleDropoffAt,
      ),
    );

    return AppSchedule.fromJson(json['schedule'] as Map<String, Object?>);
  }

  Future<AppSchedule> updateSchedule(
    String sessionToken, {
    required String familyId,
    required String scheduleId,
    required String familyMemberId,
    required String title,
    String? content,
    required DateTime startsAt,
    required DateTime endsAt,
    DateTime? vehicleBoardingAt,
    DateTime? vehicleDropoffAt,
  }) async {
    final json = await _requestJson(
      'PATCH',
      '/api/mobile/families/$familyId/schedules/$scheduleId',
      bearerToken: sessionToken,
      body: _scheduleBody(
        familyMemberId: familyMemberId,
        title: title,
        content: content,
        startsAt: startsAt,
        endsAt: endsAt,
        vehicleBoardingAt: vehicleBoardingAt,
        vehicleDropoffAt: vehicleDropoffAt,
      ),
    );

    return AppSchedule.fromJson(json['schedule'] as Map<String, Object?>);
  }

  Future<void> deleteSchedule(
    String sessionToken, {
    required String familyId,
    required String scheduleId,
  }) async {
    await _requestJson(
      'DELETE',
      '/api/mobile/families/$familyId/schedules/$scheduleId',
      bearerToken: sessionToken,
    );
  }

  Map<String, Object?> _scheduleBody({
    required String familyMemberId,
    required String title,
    String? content,
    required DateTime startsAt,
    required DateTime endsAt,
    DateTime? vehicleBoardingAt,
    DateTime? vehicleDropoffAt,
  }) {
    final body = <String, Object?>{
      'familyMemberId': familyMemberId,
      'title': title,
      'startsAt': startsAt.toUtc().toIso8601String(),
      'endsAt': endsAt.toUtc().toIso8601String(),
    };

    if (content != null) {
      body['content'] = content;
    }

    if (vehicleBoardingAt != null) {
      body['vehicleBoardingAt'] = vehicleBoardingAt.toUtc().toIso8601String();
    }

    if (vehicleDropoffAt != null) {
      body['vehicleDropoffAt'] = vehicleDropoffAt.toUtc().toIso8601String();
    }

    return body;
  }

  Future<Map<String, Object?>> _requestJson(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? bearerToken,
  }) async {
    final client = HttpClient();

    try {
      final request = await client
          .openUrl(method, _baseUrl.resolve(path))
          .timeout(_timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      if (bearerToken != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $bearerToken',
        );
      }

      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }

      final response = await request.close().timeout(_timeout);
      final responseBody = await response.transform(utf8.decoder).join();
      final decoded = responseBody.isEmpty
          ? <String, Object?>{}
          : jsonDecode(responseBody) as Map<String, Object?>;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(response.statusCode, decoded);
      }

      return decoded;
    } on SocketException catch (error) {
      throw ApiConnectionException(error.message);
    } on TimeoutException {
      throw const ApiConnectionException('요청 시간이 초과되었습니다.');
    } finally {
      client.close(force: true);
    }
  }
}

class AuthResponse {
  const AuthResponse({
    required this.tokenType,
    required this.accessToken,
    required this.expiresIn,
    required this.isNewUser,
    required this.user,
  });

  final String tokenType;
  final String accessToken;
  final int expiresIn;
  final bool isNewUser;
  final AppUser user;

  factory AuthResponse.fromJson(Map<String, Object?> json) {
    return AuthResponse(
      tokenType: json['tokenType'] as String,
      accessToken: json['accessToken'] as String,
      expiresIn: json['expiresIn'] as int,
      isNewUser: json['isNewUser'] as bool? ?? false,
      user: AppUser.fromJson(json['user'] as Map<String, Object?>),
    );
  }

  AuthResponse copyWith({AppUser? user}) {
    return AuthResponse(
      tokenType: tokenType,
      accessToken: accessToken,
      expiresIn: expiresIn,
      isNewUser: isNewUser,
      user: user ?? this.user,
    );
  }
}

class AppUser {
  const AppUser({
    required this.id,
    required this.nickname,
    required this.lastLoginAt,
  });

  final String id;
  final String nickname;
  final String? lastLoginAt;

  factory AppUser.fromJson(Map<String, Object?> json) {
    return AppUser(
      id: json['id'] as String,
      nickname: json['nickname'] as String,
      lastLoginAt: json['last_login_at'] as String?,
    );
  }
}

class AppFamily {
  const AppFamily({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String createdAt;
  final String updatedAt;

  factory AppFamily.fromJson(Map<String, Object?> json) {
    return AppFamily(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
    );
  }
}

class FamilySummary {
  const FamilySummary({
    required this.membershipId,
    required this.role,
    required this.joinedAt,
    required this.family,
  });

  final String membershipId;
  final String role;
  final String joinedAt;
  final AppFamily family;

  factory FamilySummary.fromJson(Map<String, Object?> json) {
    return FamilySummary(
      membershipId: json['membershipId'] as String,
      role: json['role'] as String,
      joinedAt: json['joinedAt'] as String,
      family: AppFamily.fromJson(json['family'] as Map<String, Object?>),
    );
  }
}

class FamilyDetail {
  const FamilyDetail({
    required this.family,
    required this.myRole,
    required this.canManage,
    required this.members,
  });

  final AppFamily family;
  final String myRole;
  final bool canManage;
  final List<FamilyMember> members;

  factory FamilyDetail.fromJson(Map<String, Object?> json) {
    final members = json['members'] as List<Object?>;

    return FamilyDetail(
      family: AppFamily.fromJson(json['family'] as Map<String, Object?>),
      myRole: json['myRole'] as String,
      canManage: json['canManage'] as bool,
      members: members
          .map(
            (member) => FamilyMember.fromJson(member as Map<String, Object?>),
          )
          .toList(),
    );
  }

  FamilyDetail copyWith({AppFamily? family, List<FamilyMember>? members}) {
    return FamilyDetail(
      family: family ?? this.family,
      myRole: myRole,
      canManage: canManage,
      members: members ?? this.members,
    );
  }
}

class FamilyMember {
  const FamilyMember({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.role,
    required this.createdAt,
    required this.userNickname,
  });

  final String id;
  final String familyId;
  final String userId;
  final String role;
  final String createdAt;
  final String userNickname;

  factory FamilyMember.fromJson(Map<String, Object?> json) {
    final user = json['user'] as Map<String, Object?>?;

    return FamilyMember(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      userId: json['user_id'] as String,
      role: json['role'] as String,
      createdAt: json['created_at'] as String,
      userNickname: user?['nickname'] as String? ?? '이름 없음',
    );
  }
}

class FamilyInvitation {
  const FamilyInvitation({
    required this.id,
    required this.familyId,
    required this.role,
    required this.inviteToken,
    required this.inviteUrl,
    required this.expiresAt,
  });

  final String id;
  final String familyId;
  final String role;
  final String inviteToken;
  final String inviteUrl;
  final String expiresAt;

  factory FamilyInvitation.fromJson(Map<String, Object?> json) {
    return FamilyInvitation(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      role: json['role'] as String,
      inviteToken: json['invite_token'] as String,
      inviteUrl: json['invite_url'] as String,
      expiresAt: json['expires_at'] as String,
    );
  }
}

class ParkingDashboard {
  const ParkingDashboard({
    required this.canManage,
    required this.vehicles,
    required this.presets,
    required this.currentLocations,
  });

  final bool canManage;
  final List<Vehicle> vehicles;
  final List<ParkingLocationPreset> presets;
  final List<ParkingRecord> currentLocations;

  factory ParkingDashboard.fromJson(Map<String, Object?> json) {
    final vehicles = json['vehicles'] as List<Object?>;
    final presets = json['presets'] as List<Object?>;
    final currentLocations = json['currentLocations'] as List<Object?>;

    return ParkingDashboard(
      canManage: json['canManage'] as bool,
      vehicles: vehicles
          .map((vehicle) => Vehicle.fromJson(vehicle as Map<String, Object?>))
          .toList(),
      presets: presets
          .map(
            (preset) =>
                ParkingLocationPreset.fromJson(preset as Map<String, Object?>),
          )
          .toList(),
      currentLocations: currentLocations
          .map(
            (record) => ParkingRecord.fromJson(record as Map<String, Object?>),
          )
          .toList(),
    );
  }
}

class Vehicle {
  const Vehicle({
    required this.id,
    required this.familyId,
    required this.nickname,
    required this.plateNumber,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String familyId;
  final String nickname;
  final String plateNumber;
  final String createdAt;
  final String updatedAt;

  factory Vehicle.fromJson(Map<String, Object?> json) {
    return Vehicle(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      nickname: json['nickname'] as String,
      plateNumber: json['plate_number'] as String,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
    );
  }
}

class ParkingLocationPreset {
  const ParkingLocationPreset({
    required this.id,
    required this.familyId,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String familyId;
  final String name;
  final int sortOrder;
  final String createdAt;
  final String updatedAt;

  factory ParkingLocationPreset.fromJson(Map<String, Object?> json) {
    return ParkingLocationPreset(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      name: json['name'] as String,
      sortOrder: json['sort_order'] as int,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
    );
  }
}

class ParkingRecord {
  const ParkingRecord({
    required this.id,
    required this.familyId,
    required this.vehicleId,
    required this.presetId,
    required this.locationText,
    required this.parkedAt,
  });

  final String id;
  final String familyId;
  final String vehicleId;
  final String? presetId;
  final String locationText;
  final String parkedAt;

  factory ParkingRecord.fromJson(Map<String, Object?> json) {
    return ParkingRecord(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      vehicleId: json['vehicle_id'] as String,
      presetId: json['preset_id'] as String?,
      locationText: json['location_text'] as String,
      parkedAt: json['parked_at'] as String,
    );
  }
}

class ScheduleDashboard {
  const ScheduleDashboard({
    required this.canManage,
    required this.members,
    required this.schedules,
  });

  final bool canManage;
  final List<FamilyMember> members;
  final List<AppSchedule> schedules;

  factory ScheduleDashboard.fromJson(Map<String, Object?> json) {
    final members = json['members'] as List<Object?>;
    final schedules = json['schedules'] as List<Object?>;

    return ScheduleDashboard(
      canManage: json['canManage'] as bool,
      members: members
          .map(
            (member) => FamilyMember.fromJson(member as Map<String, Object?>),
          )
          .toList(),
      schedules: schedules
          .map(
            (schedule) =>
                AppSchedule.fromJson(schedule as Map<String, Object?>),
          )
          .toList(),
    );
  }
}

class AppSchedule {
  const AppSchedule({
    required this.id,
    required this.familyId,
    required this.familyMemberId,
    required this.title,
    required this.content,
    required this.startsAt,
    required this.endsAt,
    required this.vehicleBoardingAt,
    required this.vehicleDropoffAt,
    required this.memberNickname,
  });

  final String id;
  final String familyId;
  final String? familyMemberId;
  final String title;
  final String? content;
  final DateTime startsAt;
  final DateTime endsAt;
  final DateTime? vehicleBoardingAt;
  final DateTime? vehicleDropoffAt;
  final String memberNickname;

  factory AppSchedule.fromJson(Map<String, Object?> json) {
    final familyMember = json['family_member'] as Map<String, Object?>?;
    final user = familyMember?['user'] as Map<String, Object?>?;

    return AppSchedule(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      familyMemberId: json['family_member_id'] as String?,
      title: json['title'] as String,
      content: json['content'] as String?,
      startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
      endsAt: DateTime.parse(json['ends_at'] as String).toLocal(),
      vehicleBoardingAt: _parseOptionalLocalDateTime(
        json['vehicle_boarding_at'] as String?,
      ),
      vehicleDropoffAt: _parseOptionalLocalDateTime(
        json['vehicle_dropoff_at'] as String?,
      ),
      memberNickname: user?['nickname'] as String? ?? '담당자 없음',
    );
  }
}

DateTime? _parseOptionalLocalDateTime(String? value) {
  if (value == null) {
    return null;
  }

  return DateTime.parse(value).toLocal();
}

class ApiException implements Exception {
  const ApiException(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;

  String? get errorCode => body['error'] as String?;

  bool get isProfileRequired =>
      statusCode == 409 && errorCode == 'profile_required';

  @override
  String toString() => 'HTTP $statusCode: ${jsonEncode(body)}';
}

class ApiConnectionException implements Exception {
  const ApiConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}
