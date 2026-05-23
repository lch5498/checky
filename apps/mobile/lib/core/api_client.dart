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
