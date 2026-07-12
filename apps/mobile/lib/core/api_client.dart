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

  Future<AuthResponse> loginWithAppleIdentityToken(
    String identityToken, {
    String? nickname,
  }) async {
    final body = <String, Object?>{'identityToken': identityToken};

    if (nickname != null) {
      body['nickname'] = nickname;
    }

    final json = await _requestJson(
      'POST',
      '/api/mobile/auth/apple',
      body: body,
    );

    return AuthResponse.fromJson(json);
  }

  Future<AppUser> getMe(String sessionToken) async {
    final json = await _requestJson(
      'GET',
      '/api/mobile/auth/me',
      bearerToken: sessionToken,
    );

    return AppUser.fromJson(json['user'] as Map<String, Object?>);
  }

  Future<AppUser> updateMyProfile(
    String sessionToken, {
    required String nickname,
    required bool updateFamilyMemberNicknames,
  }) async {
    final json = await _requestJson(
      'PATCH',
      '/api/mobile/auth/me',
      bearerToken: sessionToken,
      body: {
        'nickname': nickname,
        'updateFamilyMemberNicknames': updateFamilyMemberNicknames,
      },
    );

    return AppUser.fromJson(json['user'] as Map<String, Object?>);
  }

  Future<void> deleteMyAccount(String sessionToken) async {
    await _requestJson(
      'DELETE',
      '/api/mobile/auth/me',
      bearerToken: sessionToken,
    );
  }

  Future<void> upsertPushToken(
    String sessionToken, {
    required String token,
    required String platform,
  }) async {
    await _requestJson(
      'POST',
      '/api/mobile/push-tokens',
      bearerToken: sessionToken,
      body: {'token': token, 'platform': platform},
    );
  }

  Future<void> deletePushToken(
    String sessionToken, {
    required String token,
  }) async {
    await _requestJson(
      'DELETE',
      '/api/mobile/push-tokens',
      bearerToken: sessionToken,
      body: {'token': token},
    );
  }

  Future<List<PushNotificationHistoryItem>> getPushNotificationHistory(
    String sessionToken,
  ) async {
    final json = await _requestJson(
      'GET',
      '/api/mobile/notifications',
      bearerToken: sessionToken,
    );
    final notifications = json['notifications'] as List<Object?>? ?? const [];

    return notifications
        .map(
          (notification) => PushNotificationHistoryItem.fromJson(
            notification as Map<String, Object?>,
          ),
        )
        .toList();
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
    required String memberId,
  }) async {
    final json = await _requestJson(
      'POST',
      '/api/mobile/families/$familyId/invitations',
      bearerToken: sessionToken,
      body: {'memberId': memberId},
    );

    return FamilyInvitation.fromJson(
      json['invitation'] as Map<String, Object?>,
    );
  }

  Future<FamilyMember> createFamilyMember(
    String sessionToken, {
    required String familyId,
    required String nickname,
    required String role,
  }) async {
    final json = await _requestJson(
      'POST',
      '/api/mobile/families/$familyId/members',
      bearerToken: sessionToken,
      body: {'nickname': nickname, 'role': role},
    );

    return FamilyMember.fromJson(json['member'] as Map<String, Object?>);
  }

  Future<FamilyMember> updateFamilyMemberColor(
    String sessionToken, {
    required String familyId,
    required String memberId,
    required String color,
  }) async {
    final json = await _requestJson(
      'PATCH',
      '/api/mobile/families/$familyId/members/$memberId',
      bearerToken: sessionToken,
      body: {'color': color},
    );

    return FamilyMember.fromJson(json['member'] as Map<String, Object?>);
  }

  Future<FamilyMember> updateFamilyMemberName(
    String sessionToken, {
    required String familyId,
    required String memberId,
    required String nickname,
  }) async {
    final json = await _requestJson(
      'PATCH',
      '/api/mobile/families/$familyId/members/$memberId',
      bearerToken: sessionToken,
      body: {'nickname': nickname},
    );

    return FamilyMember.fromJson(json['member'] as Map<String, Object?>);
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
    required String presetType,
    required String name,
    String? parentPresetId,
  }) async {
    final body = <String, Object?>{'presetType': presetType, 'name': name};
    if (parentPresetId != null) {
      body['parentPresetId'] = parentPresetId;
    }

    final json = await _requestJson(
      'POST',
      '/api/mobile/families/$familyId/parking/presets',
      bearerToken: sessionToken,
      body: body,
    );

    return ParkingLocationPreset.fromJson(
      json['preset'] as Map<String, Object?>,
    );
  }

  Future<ParkingLocationPreset> updateParkingLocationPreset(
    String sessionToken, {
    required String familyId,
    required String presetId,
    required String presetType,
    required String name,
    String? parentPresetId,
  }) async {
    final body = <String, Object?>{'presetType': presetType, 'name': name};
    if (parentPresetId != null) {
      body['parentPresetId'] = parentPresetId;
    }

    final json = await _requestJson(
      'PATCH',
      '/api/mobile/families/$familyId/parking/presets/$presetId',
      bearerToken: sessionToken,
      body: body,
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
    String? buildingPresetId,
    String? floorPresetId,
    String? detailPresetId,
    required String buildingText,
    required String floorText,
    required String detailText,
  }) async {
    final body = <String, Object?>{
      'vehicleId': vehicleId,
      'buildingText': buildingText,
      'floorText': floorText,
      'detailText': detailText,
    };

    if (buildingPresetId != null) {
      body['buildingPresetId'] = buildingPresetId;
    }

    if (floorPresetId != null) {
      body['floorPresetId'] = floorPresetId;
    }

    if (detailPresetId != null) {
      body['detailPresetId'] = detailPresetId;
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
    String? educationProgramId,
    int? alertOffsetMinutes,
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
        educationProgramId: educationProgramId,
        alertOffsetMinutes: alertOffsetMinutes,
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
    String? educationProgramId,
    int? alertOffsetMinutes,
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
        educationProgramId: educationProgramId,
        alertOffsetMinutes: alertOffsetMinutes,
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

  Future<EducationProgramDashboard> getEducationProgramDashboard(
    String sessionToken, {
    required String familyId,
  }) async {
    final json = await _requestJson(
      'GET',
      '/api/mobile/families/$familyId/education-programs',
      bearerToken: sessionToken,
    );

    return EducationProgramDashboard.fromJson(json);
  }

  Future<EducationProgramMutationResult> createEducationProgram(
    String sessionToken, {
    required String familyId,
    required EducationProgramInput input,
    required CalendarApplyScope calendarApplyScope,
  }) async {
    final body = input.toJson()
      ..['calendarApplyScope'] = calendarApplyScope.toApiString();
    final json = await _requestJson(
      'POST',
      '/api/mobile/families/$familyId/education-programs',
      bearerToken: sessionToken,
      body: body,
    );

    return EducationProgramMutationResult.fromJson(json);
  }

  Future<EducationProgramMutationResult> updateEducationProgram(
    String sessionToken, {
    required String familyId,
    required String programId,
    required EducationProgramInput input,
    required CalendarApplyScope calendarApplyScope,
  }) async {
    final body = input.toJson()
      ..['calendarApplyScope'] = calendarApplyScope.toApiString();
    final json = await _requestJson(
      'PATCH',
      '/api/mobile/families/$familyId/education-programs/$programId',
      bearerToken: sessionToken,
      body: body,
    );

    return EducationProgramMutationResult.fromJson(json);
  }

  Future<void> deleteEducationProgram(
    String sessionToken, {
    required String familyId,
    required String programId,
    required CalendarApplyScope calendarApplyScope,
  }) async {
    await _requestJson(
      'DELETE',
      '/api/mobile/families/$familyId/education-programs/$programId',
      bearerToken: sessionToken,
      body: {
        'calendarApplyScope': calendarApplyScope.toApiString(),
        'timeZoneOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      },
    );
  }

  Future<AnniversaryDashboard> getAnniversaryDashboard(
    String sessionToken, {
    required String familyId,
  }) async {
    final json = await _requestJson(
      'GET',
      '/api/mobile/families/$familyId/anniversaries',
      bearerToken: sessionToken,
    );

    return AnniversaryDashboard.fromJson(json);
  }

  Future<AnniversaryMutationResult> createAnniversary(
    String sessionToken, {
    required String familyId,
    required AnniversaryInput input,
  }) async {
    final json = await _requestJson(
      'POST',
      '/api/mobile/families/$familyId/anniversaries',
      bearerToken: sessionToken,
      body: input.toJson(),
    );

    return AnniversaryMutationResult.fromJson(json);
  }

  Future<AnniversaryMutationResult> updateAnniversary(
    String sessionToken, {
    required String familyId,
    required String anniversaryId,
    required AnniversaryInput input,
  }) async {
    final json = await _requestJson(
      'PATCH',
      '/api/mobile/families/$familyId/anniversaries/$anniversaryId',
      bearerToken: sessionToken,
      body: input.toJson(),
    );

    return AnniversaryMutationResult.fromJson(json);
  }

  Future<void> deleteAnniversary(
    String sessionToken, {
    required String familyId,
    required String anniversaryId,
  }) async {
    await _requestJson(
      'DELETE',
      '/api/mobile/families/$familyId/anniversaries/$anniversaryId',
      bearerToken: sessionToken,
    );
  }

  Future<ScrapDashboard> getScrapDashboard(
    String sessionToken, {
    required String familyId,
  }) async {
    final json = await _requestJson(
      'GET',
      '/api/mobile/families/$familyId/scraps',
      bearerToken: sessionToken,
    );

    return ScrapDashboard.fromJson(json);
  }

  Future<List<ScrapRecentActivity>> getRecentScrapActivities(
    String sessionToken, {
    required String familyId,
  }) async {
    final json = await _requestJson(
      'GET',
      '/api/mobile/families/$familyId/scraps/recent',
      bearerToken: sessionToken,
    );
    final activities = json['activities'] as List<Object?>? ?? [];

    return activities
        .map(
          (item) => ScrapRecentActivity.fromJson(item as Map<String, Object?>),
        )
        .toList();
  }

  Future<ScrapChannel> createScrapChannel(
    String sessionToken, {
    required String familyId,
    required String name,
  }) async {
    final json = await _requestJson(
      'POST',
      '/api/mobile/families/$familyId/scraps',
      bearerToken: sessionToken,
      body: {'name': name},
    );

    return ScrapChannel.fromJson(json);
  }

  Future<ScrapDashboard> reorderScrapChannels(
    String sessionToken, {
    required String familyId,
    required List<String> channelIds,
  }) async {
    final json = await _requestJson(
      'PATCH',
      '/api/mobile/families/$familyId/scraps',
      bearerToken: sessionToken,
      body: {'channelIds': channelIds},
    );

    return ScrapDashboard.fromJson(json);
  }

  Future<ScrapChannel> updateScrapChannel(
    String sessionToken, {
    required String familyId,
    required String channelId,
    required String name,
  }) async {
    final json = await _requestJson(
      'PATCH',
      '/api/mobile/families/$familyId/scraps/$channelId',
      bearerToken: sessionToken,
      body: {'name': name},
    );

    return ScrapChannel.fromJson(json);
  }

  Future<void> deleteScrapChannel(
    String sessionToken, {
    required String familyId,
    required String channelId,
  }) async {
    await _requestJson(
      'DELETE',
      '/api/mobile/families/$familyId/scraps/$channelId',
      bearerToken: sessionToken,
    );
  }

  Future<ScrapLinkPreview?> previewScrapLink(
    String sessionToken, {
    required String familyId,
    required String content,
  }) async {
    final json = await _requestJson(
      'POST',
      '/api/mobile/families/$familyId/scraps/link-preview',
      bearerToken: sessionToken,
      body: {'content': content},
    );
    final preview = json['preview'] as Map<String, Object?>?;
    final linkUrl = preview?['link_url'] as String?;

    if (preview == null || linkUrl == null) {
      return null;
    }

    return ScrapLinkPreview.fromJson(preview, linkUrl: linkUrl);
  }

  Future<ScrapChannelDetail> getScrapChannel(
    String sessionToken, {
    required String familyId,
    required String channelId,
  }) async {
    final json = await _requestJson(
      'GET',
      '/api/mobile/families/$familyId/scraps/$channelId',
      bearerToken: sessionToken,
    );

    return ScrapChannelDetail.fromJson(json);
  }

  Future<ScrapPost> createScrapPost(
    String sessionToken, {
    required String familyId,
    required String channelId,
    required String content,
  }) async {
    final json = await _requestJson(
      'POST',
      '/api/mobile/families/$familyId/scraps/$channelId',
      bearerToken: sessionToken,
      body: {'content': content},
    );

    return ScrapPost.fromJson(json);
  }

  Future<ScrapPost> updateScrapPost(
    String sessionToken, {
    required String familyId,
    required String channelId,
    required String postId,
    required String content,
  }) async {
    final json = await _requestJson(
      'PATCH',
      '/api/mobile/families/$familyId/scraps/$channelId/posts/$postId',
      bearerToken: sessionToken,
      body: {'content': content},
    );

    return ScrapPost.fromJson(json);
  }

  Future<ScrapLikeResult> toggleScrapPostLike(
    String sessionToken, {
    required String familyId,
    required String channelId,
    required String postId,
  }) async {
    final json = await _requestJson(
      'POST',
      '/api/mobile/families/$familyId/scraps/$channelId/posts/$postId/like',
      bearerToken: sessionToken,
    );

    return ScrapLikeResult.fromJson(json);
  }

  Future<ScrapComment> createScrapComment(
    String sessionToken, {
    required String familyId,
    required String channelId,
    required String postId,
    required String content,
  }) async {
    final json = await _requestJson(
      'POST',
      '/api/mobile/families/$familyId/scraps/$channelId/posts/$postId/comments',
      bearerToken: sessionToken,
      body: {'content': content},
    );

    return ScrapComment.fromJson(json);
  }

  Future<ScrapComment> updateScrapComment(
    String sessionToken, {
    required String familyId,
    required String channelId,
    required String postId,
    required String commentId,
    required String content,
  }) async {
    final json = await _requestJson(
      'PATCH',
      '/api/mobile/families/$familyId/scraps/$channelId/posts/$postId/comments/$commentId',
      bearerToken: sessionToken,
      body: {'content': content},
    );

    return ScrapComment.fromJson(json);
  }

  Future<ScrapLikeResult> toggleScrapCommentLike(
    String sessionToken, {
    required String familyId,
    required String channelId,
    required String postId,
    required String commentId,
  }) async {
    final json = await _requestJson(
      'POST',
      '/api/mobile/families/$familyId/scraps/$channelId/posts/$postId/comments/$commentId/like',
      bearerToken: sessionToken,
    );

    return ScrapLikeResult.fromJson(json);
  }

  Future<void> deleteScrapPost(
    String sessionToken, {
    required String familyId,
    required String channelId,
    required String postId,
  }) async {
    await _requestJson(
      'DELETE',
      '/api/mobile/families/$familyId/scraps/$channelId/posts/$postId',
      bearerToken: sessionToken,
    );
  }

  Future<void> deleteScrapComment(
    String sessionToken, {
    required String familyId,
    required String channelId,
    required String postId,
    required String commentId,
  }) async {
    await _requestJson(
      'DELETE',
      '/api/mobile/families/$familyId/scraps/$channelId/posts/$postId/comments/$commentId',
      bearerToken: sessionToken,
    );
  }

  Future<TravelDashboard> getTravelDashboard(
    String sessionToken, {
    required String familyId,
  }) async {
    final json = await _requestJson(
      'GET',
      '/api/mobile/families/$familyId/travels',
      bearerToken: sessionToken,
    );

    return TravelDashboard.fromJson(json);
  }

  Future<List<TravelTag>> getTravelTags(
    String sessionToken, {
    required String familyId,
  }) async {
    final json = await _requestJson(
      'GET',
      '/api/mobile/families/$familyId/travels/tags',
      bearerToken: sessionToken,
    );
    final tags = json['tags'] as List<Object?>? ?? [];

    return tags
        .map((item) => TravelTag.fromJson(item as Map<String, Object?>))
        .toList();
  }

  Future<TravelTag> createTravelTag(
    String sessionToken, {
    required String familyId,
    required String name,
  }) async {
    final json = await _requestJson(
      'POST',
      '/api/mobile/families/$familyId/travels/tags',
      bearerToken: sessionToken,
      body: {'name': name},
    );

    return TravelTag.fromJson(json);
  }

  Future<TravelTag> updateTravelTag(
    String sessionToken, {
    required String familyId,
    required String tagId,
    required String name,
  }) async {
    final json = await _requestJson(
      'PATCH',
      '/api/mobile/families/$familyId/travels/tags/$tagId',
      bearerToken: sessionToken,
      body: {'name': name},
    );

    return TravelTag.fromJson(json);
  }

  Future<void> deleteTravelTag(
    String sessionToken, {
    required String familyId,
    required String tagId,
  }) async {
    await _requestJson(
      'DELETE',
      '/api/mobile/families/$familyId/travels/tags/$tagId',
      bearerToken: sessionToken,
    );
  }

  Future<List<TravelChecklistItem>> getTravelChecklistItems(
    String sessionToken, {
    required String familyId,
  }) async {
    final json = await _requestJson(
      'GET',
      '/api/mobile/families/$familyId/travels/checklist-items',
      bearerToken: sessionToken,
    );
    final items = json['items'] as List<Object?>? ?? [];

    return items
        .map(
          (item) => TravelChecklistItem.fromJson(item as Map<String, Object?>),
        )
        .toList();
  }

  Future<TravelChecklistItem> createTravelChecklistItem(
    String sessionToken, {
    required String familyId,
    required String name,
    String? parentId,
  }) async {
    final body = <String, Object?>{'name': name};
    if (parentId != null) {
      body['parentId'] = parentId;
    }

    final json = await _requestJson(
      'POST',
      '/api/mobile/families/$familyId/travels/checklist-items',
      bearerToken: sessionToken,
      body: body,
    );

    return TravelChecklistItem.fromJson(json);
  }

  Future<TravelChecklistItem> updateTravelChecklistItem(
    String sessionToken, {
    required String familyId,
    required String itemId,
    required String name,
  }) async {
    final json = await _requestJson(
      'PATCH',
      '/api/mobile/families/$familyId/travels/checklist-items/$itemId',
      bearerToken: sessionToken,
      body: {'name': name},
    );

    return TravelChecklistItem.fromJson(json);
  }

  Future<void> deleteTravelChecklistItem(
    String sessionToken, {
    required String familyId,
    required String itemId,
  }) async {
    await _requestJson(
      'DELETE',
      '/api/mobile/families/$familyId/travels/checklist-items/$itemId',
      bearerToken: sessionToken,
    );
  }

  Future<List<TravelChecklistItem>> saveTravelTripChecklistItemsToFavorites(
    String sessionToken, {
    required String familyId,
    required String tripId,
  }) async {
    final json = await _requestJson(
      'POST',
      '/api/mobile/families/$familyId/travels/$tripId/checklist-items/favorites',
      bearerToken: sessionToken,
    );
    final items = json['items'] as List<Object?>? ?? [];

    return items
        .map(
          (item) => TravelChecklistItem.fromJson(item as Map<String, Object?>),
        )
        .toList();
  }

  Future<TravelTrip> createTravelTrip(
    String sessionToken, {
    required String familyId,
    required String title,
    required DateTime startsOn,
    required DateTime endsOn,
  }) async {
    final json = await _requestJson(
      'POST',
      '/api/mobile/families/$familyId/travels',
      bearerToken: sessionToken,
      body: {
        'title': title,
        'startsOn': _dateOnlyString(startsOn),
        'endsOn': _dateOnlyString(endsOn),
      },
    );

    return TravelTrip.fromJson(json);
  }

  Future<TravelTrip> updateTravelTrip(
    String sessionToken, {
    required String familyId,
    required String tripId,
    required String title,
    required DateTime startsOn,
    required DateTime endsOn,
  }) async {
    final json = await _requestJson(
      'PATCH',
      '/api/mobile/families/$familyId/travels/$tripId',
      bearerToken: sessionToken,
      body: {
        'title': title,
        'startsOn': _dateOnlyString(startsOn),
        'endsOn': _dateOnlyString(endsOn),
      },
    );

    return TravelTrip.fromJson(json);
  }

  Future<void> deleteTravelTrip(
    String sessionToken, {
    required String familyId,
    required String tripId,
  }) async {
    await _requestJson(
      'DELETE',
      '/api/mobile/families/$familyId/travels/$tripId',
      bearerToken: sessionToken,
    );
  }

  Future<TravelTripDetail> getTravelTripDetail(
    String sessionToken, {
    required String familyId,
    required String tripId,
  }) async {
    final json = await _requestJson(
      'GET',
      '/api/mobile/families/$familyId/travels/$tripId',
      bearerToken: sessionToken,
    );

    return TravelTripDetail.fromJson(json);
  }

  Future<List<TravelTripChecklistItem>> getTravelTripChecklistItems(
    String sessionToken, {
    required String familyId,
    required String tripId,
  }) async {
    final json = await _requestJson(
      'GET',
      '/api/mobile/families/$familyId/travels/$tripId/checklist-items',
      bearerToken: sessionToken,
    );
    final items = json['items'] as List<Object?>? ?? [];

    return items
        .map(
          (item) =>
              TravelTripChecklistItem.fromJson(item as Map<String, Object?>),
        )
        .toList();
  }

  Future<TravelTripChecklistItem> createTravelTripChecklistItem(
    String sessionToken, {
    required String familyId,
    required String tripId,
    required String name,
    String? parentId,
  }) async {
    final body = <String, Object?>{'name': name};
    if (parentId != null) {
      body['parentId'] = parentId;
    }

    final json = await _requestJson(
      'POST',
      '/api/mobile/families/$familyId/travels/$tripId/checklist-items',
      bearerToken: sessionToken,
      body: body,
    );

    return TravelTripChecklistItem.fromJson(json);
  }

  Future<TravelTripChecklistItem> updateTravelTripChecklistItem(
    String sessionToken, {
    required String familyId,
    required String tripId,
    required String itemId,
    String? name,
    bool? isChecked,
  }) async {
    final body = <String, Object?>{};
    if (name != null) {
      body['name'] = name;
    }
    if (isChecked != null) {
      body['isChecked'] = isChecked;
    }

    final json = await _requestJson(
      'PATCH',
      '/api/mobile/families/$familyId/travels/$tripId/checklist-items/$itemId',
      bearerToken: sessionToken,
      body: body,
    );

    return TravelTripChecklistItem.fromJson(json);
  }

  Future<void> deleteTravelTripChecklistItem(
    String sessionToken, {
    required String familyId,
    required String tripId,
    required String itemId,
  }) async {
    await _requestJson(
      'DELETE',
      '/api/mobile/families/$familyId/travels/$tripId/checklist-items/$itemId',
      bearerToken: sessionToken,
    );
  }

  Future<TravelItinerary> createTravelItinerary(
    String sessionToken, {
    required String familyId,
    required String tripId,
    required DateTime itineraryDate,
    required String title,
    String? content,
    String? mapUrl,
    TimeOfDayValue? startsAt,
    List<String> tagNames = const [],
  }) async {
    final json = await _requestJson(
      'POST',
      '/api/mobile/families/$familyId/travels/$tripId/itineraries',
      bearerToken: sessionToken,
      body: _travelItineraryBody(
        itineraryDate: itineraryDate,
        title: title,
        content: content,
        mapUrl: mapUrl,
        startsAt: startsAt,
        tagNames: tagNames,
      ),
    );

    return TravelItinerary.fromJson(json);
  }

  Future<TravelItinerary> updateTravelItinerary(
    String sessionToken, {
    required String familyId,
    required String tripId,
    required String itineraryId,
    required DateTime itineraryDate,
    required String title,
    String? content,
    String? mapUrl,
    TimeOfDayValue? startsAt,
    List<String> tagNames = const [],
  }) async {
    final json = await _requestJson(
      'PATCH',
      '/api/mobile/families/$familyId/travels/$tripId/itineraries/$itineraryId',
      bearerToken: sessionToken,
      body: _travelItineraryBody(
        itineraryDate: itineraryDate,
        title: title,
        content: content,
        mapUrl: mapUrl,
        startsAt: startsAt,
        tagNames: tagNames,
      ),
    );

    return TravelItinerary.fromJson(json);
  }

  Future<void> deleteTravelItinerary(
    String sessionToken, {
    required String familyId,
    required String tripId,
    required String itineraryId,
  }) async {
    await _requestJson(
      'DELETE',
      '/api/mobile/families/$familyId/travels/$tripId/itineraries/$itineraryId',
      bearerToken: sessionToken,
    );
  }

  Future<TravelTripDetail> reorderTravelItineraries(
    String sessionToken, {
    required String familyId,
    required String tripId,
    required List<TravelItineraryOrderInput> items,
  }) async {
    final json = await _requestJson(
      'PATCH',
      '/api/mobile/families/$familyId/travels/$tripId/itineraries',
      bearerToken: sessionToken,
      body: {'items': items.map((item) => item.toJson()).toList()},
    );

    return TravelTripDetail.fromJson(json);
  }

  Map<String, Object?> _travelItineraryBody({
    required DateTime itineraryDate,
    required String title,
    String? content,
    String? mapUrl,
    TimeOfDayValue? startsAt,
    List<String> tagNames = const [],
  }) {
    final body = <String, Object?>{
      'itineraryDate': _dateOnlyString(itineraryDate),
      'title': title,
      'content': content,
      'mapUrl': mapUrl,
      'tagNames': tagNames,
    };

    if (startsAt != null) {
      body['startsAt'] = startsAt.toApiString();
    }

    return body;
  }

  Map<String, Object?> _scheduleBody({
    required String familyMemberId,
    required String title,
    String? content,
    required DateTime startsAt,
    required DateTime endsAt,
    DateTime? vehicleBoardingAt,
    DateTime? vehicleDropoffAt,
    String? educationProgramId,
    int? alertOffsetMinutes,
  }) {
    final body = <String, Object?>{
      'familyMemberId': familyMemberId,
      'title': title,
      'startsAt': startsAt.toUtc().toIso8601String(),
      'endsAt': endsAt.toUtc().toIso8601String(),
      'alertOffsetMinutes': alertOffsetMinutes,
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

    if (educationProgramId != null) {
      body['educationTemplateId'] = educationProgramId;
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

class PushNotificationHistoryItem {
  const PushNotificationHistoryItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.familyName,
    required this.sentAt,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final String? familyName;
  final DateTime sentAt;

  factory PushNotificationHistoryItem.fromJson(Map<String, Object?> json) {
    return PushNotificationHistoryItem(
      id: json['id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      familyName: json['familyName'] as String?,
      sentAt: DateTime.parse(json['sentAt'] as String).toLocal(),
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
    required this.nickname,
    required this.role,
    required this.color,
    required this.createdAt,
    required this.userNickname,
  });

  final String id;
  final String familyId;
  final String? userId;
  final String nickname;
  final String role;
  final String? color;
  final String createdAt;
  final String userNickname;

  bool get isLinked => userId != null;

  factory FamilyMember.fromJson(Map<String, Object?> json) {
    final nickname = json['nickname'] as String? ?? '이름 없음';

    return FamilyMember(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      userId: json['user_id'] as String?,
      nickname: nickname,
      role: json['role'] as String,
      color: json['color'] as String?,
      createdAt: json['created_at'] as String,
      userNickname: nickname,
    );
  }
}

class FamilyInvitation {
  const FamilyInvitation({
    required this.id,
    required this.familyId,
    required this.memberId,
    required this.memberNickname,
    required this.role,
    required this.inviteToken,
    required this.inviteUrl,
    required this.expiresAt,
  });

  final String id;
  final String familyId;
  final String memberId;
  final String memberNickname;
  final String role;
  final String inviteToken;
  final String inviteUrl;
  final String expiresAt;

  factory FamilyInvitation.fromJson(Map<String, Object?> json) {
    return FamilyInvitation(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      memberId: json['family_member_id'] as String,
      memberNickname: json['member_nickname'] as String? ?? '구성원',
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
    required this.parentPresetId,
    required this.presetType,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String familyId;
  final String? parentPresetId;
  final String presetType;
  final String name;
  final int sortOrder;
  final String createdAt;
  final String updatedAt;

  factory ParkingLocationPreset.fromJson(Map<String, Object?> json) {
    return ParkingLocationPreset(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      parentPresetId: json['parent_preset_id'] as String?,
      presetType: json['preset_type'] as String,
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
    required this.buildingPresetId,
    required this.floorPresetId,
    required this.detailPresetId,
    required this.buildingText,
    required this.floorText,
    required this.detailText,
    required this.locationText,
    required this.createdByUserId,
    required this.createdByNickname,
    required this.parkedAt,
    required this.updatedAt,
  });

  final String id;
  final String familyId;
  final String vehicleId;
  final String? buildingPresetId;
  final String? floorPresetId;
  final String? detailPresetId;
  final String buildingText;
  final String floorText;
  final String detailText;
  final String locationText;
  final String? createdByUserId;
  final String createdByNickname;
  final String parkedAt;
  final String updatedAt;

  factory ParkingRecord.fromJson(Map<String, Object?> json) {
    final createdByUser = json['created_by_user'] as Map<String, Object?>?;

    return ParkingRecord(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      vehicleId: json['vehicle_id'] as String,
      buildingPresetId: json['building_preset_id'] as String?,
      floorPresetId: json['floor_preset_id'] as String?,
      detailPresetId: json['detail_preset_id'] as String?,
      buildingText: json['building_text'] as String,
      floorText: json['floor_text'] as String,
      detailText: json['detail_text'] as String,
      locationText: json['location_text'] as String,
      createdByUserId: json['created_by_user_id'] as String?,
      createdByNickname: createdByUser?['nickname'] as String? ?? '알 수 없음',
      parkedAt: json['parked_at'] as String,
      updatedAt: json['updated_at'] as String,
    );
  }
}

class ScheduleDashboard {
  const ScheduleDashboard({
    required this.canManage,
    required this.members,
    required this.schedules,
    required this.educationPrograms,
  });

  final bool canManage;
  final List<FamilyMember> members;
  final List<AppSchedule> schedules;
  final List<EducationProgram> educationPrograms;

  factory ScheduleDashboard.fromJson(Map<String, Object?> json) {
    final members = json['members'] as List<Object?>;
    final schedules = json['schedules'] as List<Object?>;
    final educationPrograms =
        json['educationPrograms'] as List<Object?>? ?? const <Object?>[];

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
      educationPrograms: educationPrograms
          .map(
            (program) =>
                EducationProgram.fromJson(program as Map<String, Object?>),
          )
          .toList(),
    );
  }
}

class EducationProgramDashboard {
  const EducationProgramDashboard({
    required this.canManage,
    required this.members,
    required this.programs,
  });

  final bool canManage;
  final List<FamilyMember> members;
  final List<EducationProgram> programs;

  factory EducationProgramDashboard.fromJson(Map<String, Object?> json) {
    final members = json['members'] as List<Object?>;
    final programs = json['programs'] as List<Object?>;

    return EducationProgramDashboard(
      canManage: json['canManage'] as bool,
      members: members
          .map(
            (member) => FamilyMember.fromJson(member as Map<String, Object?>),
          )
          .toList(),
      programs: programs
          .map(
            (program) =>
                EducationProgram.fromJson(program as Map<String, Object?>),
          )
          .toList(),
    );
  }
}

class EducationProgramMutationResult {
  const EducationProgramMutationResult({
    required this.program,
    required this.generatedScheduleCount,
  });

  final EducationProgram program;
  final int generatedScheduleCount;

  factory EducationProgramMutationResult.fromJson(Map<String, Object?> json) {
    return EducationProgramMutationResult(
      program: EducationProgram.fromJson(
        json['program'] as Map<String, Object?>,
      ),
      generatedScheduleCount: json['generatedScheduleCount'] as int,
    );
  }
}

enum CalendarApplyScope {
  all,
  future;

  String toApiString() {
    return switch (this) {
      CalendarApplyScope.all => 'all',
      CalendarApplyScope.future => 'future',
    };
  }
}

enum EducationRecurrenceType {
  weekly,
  monthly;

  String toApiString() {
    return switch (this) {
      EducationRecurrenceType.weekly => 'weekly',
      EducationRecurrenceType.monthly => 'monthly',
    };
  }

  static EducationRecurrenceType fromJson(Object? value) {
    return switch (value) {
      'monthly' => EducationRecurrenceType.monthly,
      _ => EducationRecurrenceType.weekly,
    };
  }
}

enum AnniversaryCategory {
  birthday,
  wedding,
  custom;

  String toApiString() {
    return switch (this) {
      AnniversaryCategory.birthday => 'birthday',
      AnniversaryCategory.wedding => 'wedding',
      AnniversaryCategory.custom => 'custom',
    };
  }

  static AnniversaryCategory fromJson(Object? value) {
    return switch (value) {
      'birthday' => AnniversaryCategory.birthday,
      'wedding' => AnniversaryCategory.wedding,
      _ => AnniversaryCategory.custom,
    };
  }
}

enum AnniversaryCalendarType {
  solar,
  lunar;

  String toApiString() {
    return switch (this) {
      AnniversaryCalendarType.solar => 'solar',
      AnniversaryCalendarType.lunar => 'lunar',
    };
  }

  static AnniversaryCalendarType fromJson(Object? value) {
    return value == 'lunar'
        ? AnniversaryCalendarType.lunar
        : AnniversaryCalendarType.solar;
  }
}

class AnniversaryInput {
  const AnniversaryInput({
    required this.category,
    required this.customCategoryLabel,
    required this.title,
    required this.calendarType,
    required this.month,
    required this.day,
    required this.isLunarLeap,
    required this.year,
    required this.alertOffsetMinutes,
  });

  final AnniversaryCategory category;
  final String? customCategoryLabel;
  final String title;
  final AnniversaryCalendarType calendarType;
  final int month;
  final int day;
  final bool isLunarLeap;
  final int? year;
  final int? alertOffsetMinutes;

  Map<String, Object?> toJson() {
    return {
      'category': category.toApiString(),
      'customCategoryLabel': customCategoryLabel,
      'title': title,
      'calendarType': calendarType.toApiString(),
      'month': month,
      'day': day,
      'isLunarLeap': isLunarLeap,
      'year': year,
      'alertOffsetMinutes': alertOffsetMinutes,
      'timeZoneOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
    };
  }
}

class ScrapDashboard {
  const ScrapDashboard({required this.channels});

  final List<ScrapChannel> channels;

  factory ScrapDashboard.fromJson(Map<String, Object?> json) {
    final channels = json['channels'] as List<Object?>? ?? [];

    return ScrapDashboard(
      channels: channels
          .map((item) => ScrapChannel.fromJson(item as Map<String, Object?>))
          .toList(),
    );
  }
}

class ScrapRecentActivity {
  const ScrapRecentActivity({
    required this.id,
    required this.type,
    required this.postId,
    required this.channelId,
    required this.channelName,
    required this.content,
    required this.authorNickname,
    required this.createdAt,
  });

  final String id;
  final ScrapRecentActivityType type;
  final String postId;
  final String channelId;
  final String channelName;
  final String content;
  final String authorNickname;
  final DateTime createdAt;

  factory ScrapRecentActivity.fromJson(Map<String, Object?> json) {
    return ScrapRecentActivity(
      id: json['id'] as String,
      type: ScrapRecentActivityType.fromApiValue(json['type'] as String),
      postId: json['post_id'] as String,
      channelId: json['channel_id'] as String,
      channelName: json['channel_name'] as String,
      content: json['content'] as String,
      authorNickname: json['authorNickname'] as String? ?? '알 수 없음',
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }
}

enum ScrapRecentActivityType {
  post,
  comment;

  factory ScrapRecentActivityType.fromApiValue(String value) {
    return switch (value) {
      'post' => ScrapRecentActivityType.post,
      'comment' => ScrapRecentActivityType.comment,
      _ => throw FormatException('Unknown scrap activity type: $value'),
    };
  }
}

class ScrapChannelDetail {
  const ScrapChannelDetail({required this.channel, required this.posts});

  final ScrapChannel channel;
  final List<ScrapPost> posts;

  factory ScrapChannelDetail.fromJson(Map<String, Object?> json) {
    final posts = json['posts'] as List<Object?>? ?? [];

    return ScrapChannelDetail(
      channel: ScrapChannel.fromJson(json['channel'] as Map<String, Object?>),
      posts: posts
          .map((item) => ScrapPost.fromJson(item as Map<String, Object?>))
          .toList(),
    );
  }
}

class ScrapChannel {
  const ScrapChannel({
    required this.id,
    required this.familyId,
    required this.name,
    required this.sortOrder,
    required this.authorNickname,
    required this.canEdit,
    required this.canDelete,
    required this.hasRecentPosts,
    this.latestPostCreatedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String familyId;
  final String name;
  final int? sortOrder;
  final String authorNickname;
  final bool canEdit;
  final bool canDelete;
  final bool hasRecentPosts;
  final DateTime? latestPostCreatedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ScrapChannel.fromJson(Map<String, Object?> json) {
    return ScrapChannel(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      name: json['name'] as String,
      sortOrder: json['sort_order'] as int?,
      authorNickname: json['authorNickname'] as String? ?? '알 수 없음',
      canEdit: json['canEdit'] as bool? ?? false,
      canDelete: json['canDelete'] as bool? ?? false,
      hasRecentPosts: json['hasRecentPosts'] as bool? ?? false,
      latestPostCreatedAt: (json['latestPostCreatedAt'] as String?) == null
          ? null
          : DateTime.parse(json['latestPostCreatedAt'] as String).toLocal(),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
    );
  }

  ScrapChannel copyWith({bool? hasRecentPosts}) {
    return ScrapChannel(
      id: id,
      familyId: familyId,
      name: name,
      sortOrder: sortOrder,
      authorNickname: authorNickname,
      canEdit: canEdit,
      canDelete: canDelete,
      hasRecentPosts: hasRecentPosts ?? this.hasRecentPosts,
      latestPostCreatedAt: latestPostCreatedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class ScrapPost {
  const ScrapPost({
    required this.id,
    required this.familyId,
    required this.channelId,
    required this.content,
    required this.linkPreview,
    required this.authorNickname,
    required this.canEdit,
    required this.canDelete,
    required this.likeCount,
    required this.isLikedByMe,
    required this.createdAt,
    required this.updatedAt,
    required this.comments,
  });

  final String id;
  final String familyId;
  final String channelId;
  final String content;
  final ScrapLinkPreview? linkPreview;
  final String authorNickname;
  final bool canEdit;
  final bool canDelete;
  final int likeCount;
  final bool isLikedByMe;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ScrapComment> comments;

  factory ScrapPost.fromJson(Map<String, Object?> json) {
    final comments = json['comments'] as List<Object?>? ?? [];
    final linkUrl = json['link_url'] as String?;

    return ScrapPost(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      channelId: json['channel_id'] as String,
      content: json['content'] as String,
      linkPreview: linkUrl == null
          ? null
          : ScrapLinkPreview.fromJson(json, linkUrl: linkUrl),
      authorNickname: json['authorNickname'] as String? ?? '알 수 없음',
      canEdit: json['canEdit'] as bool? ?? false,
      canDelete: json['canDelete'] as bool? ?? false,
      likeCount: json['likeCount'] as int? ?? 0,
      isLikedByMe: json['isLikedByMe'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
      comments: comments
          .map((item) => ScrapComment.fromJson(item as Map<String, Object?>))
          .toList(),
    );
  }

  ScrapPost copyWith({
    int? likeCount,
    bool? isLikedByMe,
    List<ScrapComment>? comments,
  }) {
    return ScrapPost(
      id: id,
      familyId: familyId,
      channelId: channelId,
      content: content,
      linkPreview: linkPreview,
      authorNickname: authorNickname,
      canEdit: canEdit,
      canDelete: canDelete,
      likeCount: likeCount ?? this.likeCount,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      createdAt: createdAt,
      updatedAt: updatedAt,
      comments: comments ?? this.comments,
    );
  }
}

class ScrapComment {
  const ScrapComment({
    required this.id,
    required this.familyId,
    required this.postId,
    required this.content,
    required this.authorNickname,
    required this.canEdit,
    required this.canDelete,
    required this.likeCount,
    required this.isLikedByMe,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String familyId;
  final String postId;
  final String content;
  final String authorNickname;
  final bool canEdit;
  final bool canDelete;
  final int likeCount;
  final bool isLikedByMe;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ScrapComment.fromJson(Map<String, Object?> json) {
    return ScrapComment(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      postId: json['post_id'] as String,
      content: json['content'] as String,
      authorNickname: json['authorNickname'] as String? ?? '알 수 없음',
      canEdit: json['canEdit'] as bool? ?? false,
      canDelete: json['canDelete'] as bool? ?? false,
      likeCount: json['likeCount'] as int? ?? 0,
      isLikedByMe: json['isLikedByMe'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
    );
  }

  ScrapComment copyWith({int? likeCount, bool? isLikedByMe}) {
    return ScrapComment(
      id: id,
      familyId: familyId,
      postId: postId,
      content: content,
      authorNickname: authorNickname,
      canEdit: canEdit,
      canDelete: canDelete,
      likeCount: likeCount ?? this.likeCount,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class ScrapLikeResult {
  const ScrapLikeResult({required this.likeCount, required this.isLikedByMe});

  final int likeCount;
  final bool isLikedByMe;

  factory ScrapLikeResult.fromJson(Map<String, Object?> json) {
    return ScrapLikeResult(
      likeCount: json['likeCount'] as int? ?? 0,
      isLikedByMe: json['isLikedByMe'] as bool? ?? false,
    );
  }
}

class ScrapLinkPreview {
  const ScrapLinkPreview({
    required this.url,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.siteName,
  });

  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;

  factory ScrapLinkPreview.fromJson(
    Map<String, Object?> json, {
    required String linkUrl,
  }) {
    return ScrapLinkPreview(
      url: linkUrl,
      title: json['link_title'] as String?,
      description: json['link_description'] as String?,
      imageUrl: json['link_image_url'] as String?,
      siteName: json['link_site_name'] as String?,
    );
  }
}

class TravelDashboard {
  const TravelDashboard({required this.trips});

  final List<TravelTrip> trips;

  factory TravelDashboard.fromJson(Map<String, Object?> json) {
    final trips = json['trips'] as List<Object?>? ?? [];

    return TravelDashboard(
      trips: trips
          .map((item) => TravelTrip.fromJson(item as Map<String, Object?>))
          .toList(),
    );
  }
}

class TravelTripDetail {
  const TravelTripDetail({
    required this.trip,
    required this.itineraries,
    required this.tags,
    required this.checklistItems,
  });

  final TravelTrip trip;
  final List<TravelItinerary> itineraries;
  final List<TravelTag> tags;
  final List<TravelTripChecklistItem> checklistItems;

  factory TravelTripDetail.fromJson(Map<String, Object?> json) {
    final itineraries = json['itineraries'] as List<Object?>? ?? [];
    final tags = json['tags'] as List<Object?>? ?? [];
    final checklistItems = json['checklistItems'] as List<Object?>? ?? [];

    return TravelTripDetail(
      trip: TravelTrip.fromJson(json['trip'] as Map<String, Object?>),
      itineraries: itineraries
          .map((item) => TravelItinerary.fromJson(item as Map<String, Object?>))
          .toList(),
      tags: tags
          .map((item) => TravelTag.fromJson(item as Map<String, Object?>))
          .toList(),
      checklistItems: checklistItems
          .map(
            (item) =>
                TravelTripChecklistItem.fromJson(item as Map<String, Object?>),
          )
          .toList(),
    );
  }
}

class TravelTrip {
  const TravelTrip({
    required this.id,
    required this.familyId,
    required this.title,
    required this.startsOn,
    required this.endsOn,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String familyId;
  final String title;
  final DateTime startsOn;
  final DateTime endsOn;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory TravelTrip.fromJson(Map<String, Object?> json) {
    return TravelTrip(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      title: json['title'] as String,
      startsOn: DateTime.parse(json['starts_on'] as String),
      endsOn: DateTime.parse(json['ends_on'] as String),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
    );
  }
}

class TravelItinerary {
  const TravelItinerary({
    required this.id,
    required this.familyId,
    required this.tripId,
    required this.itineraryDate,
    required this.title,
    required this.content,
    required this.mapUrl,
    required this.startsAt,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    required this.tags,
  });

  final String id;
  final String familyId;
  final String tripId;
  final DateTime itineraryDate;
  final String title;
  final String? content;
  final String? mapUrl;
  final TimeOfDayValue? startsAt;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<TravelTag> tags;

  factory TravelItinerary.fromJson(Map<String, Object?> json) {
    final tags = json['tags'] as List<Object?>? ?? [];

    return TravelItinerary(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      tripId: json['trip_id'] as String,
      itineraryDate: DateTime.parse(json['itinerary_date'] as String),
      title: json['title'] as String,
      content: json['content'] as String?,
      mapUrl: json['map_url'] as String?,
      startsAt: _parseOptionalTimeOfDayValue(json['starts_at'] as String?),
      sortOrder: json['sort_order'] as int? ?? 1,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
      tags: tags
          .map((item) => TravelTag.fromJson(item as Map<String, Object?>))
          .toList(),
    );
  }

  TravelItinerary copyWith({DateTime? itineraryDate, int? sortOrder}) {
    return TravelItinerary(
      id: id,
      familyId: familyId,
      tripId: tripId,
      itineraryDate: itineraryDate ?? this.itineraryDate,
      title: title,
      content: content,
      mapUrl: mapUrl,
      startsAt: startsAt,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt,
      tags: tags,
    );
  }
}

class TravelTag {
  const TravelTag({
    required this.id,
    required this.familyId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String familyId;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory TravelTag.fromJson(Map<String, Object?> json) {
    return TravelTag(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
    );
  }
}

class TravelChecklistItem {
  const TravelChecklistItem({
    required this.id,
    required this.familyId,
    required this.parentId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String familyId;
  final String? parentId;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory TravelChecklistItem.fromJson(Map<String, Object?> json) {
    return TravelChecklistItem(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      parentId: json['parent_id'] as String?,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
    );
  }
}

class TravelTripChecklistItem {
  const TravelTripChecklistItem({
    required this.id,
    required this.familyId,
    required this.tripId,
    required this.parentId,
    required this.name,
    required this.isChecked,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String familyId;
  final String tripId;
  final String? parentId;
  final String name;
  final bool isChecked;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory TravelTripChecklistItem.fromJson(Map<String, Object?> json) {
    return TravelTripChecklistItem(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      tripId: json['trip_id'] as String,
      parentId: json['parent_id'] as String?,
      name: json['name'] as String,
      isChecked: json['is_checked'] as bool? ?? false,
      sortOrder: json['sort_order'] as int? ?? 1,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
    );
  }

  TravelTripChecklistItem copyWith({bool? isChecked}) {
    return TravelTripChecklistItem(
      id: id,
      familyId: familyId,
      tripId: tripId,
      parentId: parentId,
      name: name,
      isChecked: isChecked ?? this.isChecked,
      sortOrder: sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class TravelItineraryOrderInput {
  const TravelItineraryOrderInput({
    required this.id,
    required this.itineraryDate,
  });

  final String id;
  final DateTime itineraryDate;

  Map<String, Object?> toJson() {
    return {'id': id, 'itineraryDate': _dateOnlyString(itineraryDate)};
  }
}

class AnniversaryDashboard {
  const AnniversaryDashboard({
    required this.canManage,
    required this.anniversaries,
  });

  final bool canManage;
  final List<Anniversary> anniversaries;

  factory AnniversaryDashboard.fromJson(Map<String, Object?> json) {
    final anniversaries = json['anniversaries'] as List<Object?>;

    return AnniversaryDashboard(
      canManage: json['canManage'] as bool,
      anniversaries: anniversaries
          .map((item) => Anniversary.fromJson(item as Map<String, Object?>))
          .toList(),
    );
  }
}

class AnniversaryMutationResult {
  const AnniversaryMutationResult({
    required this.anniversary,
    required this.generatedScheduleCount,
  });

  final Anniversary anniversary;
  final int generatedScheduleCount;

  factory AnniversaryMutationResult.fromJson(Map<String, Object?> json) {
    return AnniversaryMutationResult(
      anniversary: Anniversary.fromJson(
        json['anniversary'] as Map<String, Object?>,
      ),
      generatedScheduleCount: json['generatedScheduleCount'] as int,
    );
  }
}

class Anniversary {
  const Anniversary({
    required this.id,
    required this.familyId,
    required this.category,
    required this.customCategoryLabel,
    required this.title,
    required this.calendarType,
    required this.month,
    required this.day,
    required this.isLunarLeap,
    required this.year,
    required this.alertOffsetMinutes,
    required this.nextOccurrenceDate,
    required this.nextOccurrenceOrdinal,
    required this.elapsedDays,
    required this.recentSchedules,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String familyId;
  final AnniversaryCategory category;
  final String? customCategoryLabel;
  final String title;
  final AnniversaryCalendarType calendarType;
  final int month;
  final int day;
  final bool isLunarLeap;
  final int? year;
  final int? alertOffsetMinutes;
  final DateTime? nextOccurrenceDate;
  final int? nextOccurrenceOrdinal;
  final int? elapsedDays;
  final List<AnniversaryScheduleOccurrence> recentSchedules;
  final String createdAt;
  final String updatedAt;

  factory Anniversary.fromJson(Map<String, Object?> json) {
    final nextOccurrenceDate = json['nextOccurrenceDate'] as String?;
    final recentSchedules = json['recentSchedules'] as List<Object?>? ?? [];

    return Anniversary(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      category: AnniversaryCategory.fromJson(json['category']),
      customCategoryLabel: json['custom_category_label'] as String?,
      title: json['title'] as String,
      calendarType: AnniversaryCalendarType.fromJson(json['calendar_type']),
      month: json['month'] as int,
      day: json['day'] as int,
      isLunarLeap: json['is_lunar_leap'] as bool? ?? false,
      year: json['year'] as int?,
      alertOffsetMinutes: json['alert_offset_minutes'] as int?,
      nextOccurrenceDate: nextOccurrenceDate == null
          ? null
          : DateTime.parse(nextOccurrenceDate),
      nextOccurrenceOrdinal: json['nextOccurrenceOrdinal'] as int?,
      elapsedDays: json['elapsedDays'] as int?,
      recentSchedules: recentSchedules
          .map(
            (schedule) => AnniversaryScheduleOccurrence.fromJson(
              schedule as Map<String, Object?>,
            ),
          )
          .toList(),
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
    );
  }
}

class AnniversaryScheduleOccurrence {
  const AnniversaryScheduleOccurrence({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.endsAt,
  });

  final String id;
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;

  factory AnniversaryScheduleOccurrence.fromJson(Map<String, Object?> json) {
    return AnniversaryScheduleOccurrence(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
      endsAt: DateTime.parse(json['ends_at'] as String).toLocal(),
    );
  }
}

class EducationProgramInput {
  const EducationProgramInput({
    required this.familyMemberId,
    required this.name,
    required this.startsOn,
    required this.endsOn,
    required this.recurrenceType,
    required this.weeklySchedules,
    required this.monthlySchedules,
    required this.phoneContacts,
    required this.alertOffsetMinutes,
  });

  final String familyMemberId;
  final String name;
  final DateTime startsOn;
  final DateTime endsOn;
  final EducationRecurrenceType recurrenceType;
  final List<EducationWeeklySchedule> weeklySchedules;
  final List<EducationMonthlySchedule> monthlySchedules;
  final List<EducationProgramPhoneContact> phoneContacts;
  final int? alertOffsetMinutes;

  EducationProgramInput copyWithFamilyMemberId(String familyMemberId) {
    return EducationProgramInput(
      familyMemberId: familyMemberId,
      name: name,
      startsOn: startsOn,
      endsOn: endsOn,
      recurrenceType: recurrenceType,
      weeklySchedules: weeklySchedules,
      monthlySchedules: monthlySchedules,
      phoneContacts: phoneContacts,
      alertOffsetMinutes: alertOffsetMinutes,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'familyMemberId': familyMemberId,
      'name': name,
      'startsOn': _dateOnlyString(startsOn),
      'endsOn': _dateOnlyString(endsOn),
      'recurrenceType': recurrenceType.toApiString(),
      'weeklySchedules': weeklySchedules
          .map((schedule) => schedule.toJson())
          .toList(),
      'monthlySchedules': monthlySchedules
          .map((schedule) => schedule.toJson())
          .toList(),
      'phoneContacts': phoneContacts
          .map((contact) => contact.toJson())
          .toList(),
      'alertOffsetMinutes': alertOffsetMinutes,
      'timeZoneOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
    };
  }
}

class EducationProgram {
  const EducationProgram({
    required this.id,
    required this.familyId,
    required this.familyMemberId,
    required this.name,
    required this.startsOn,
    required this.endsOn,
    required this.recurrenceType,
    required this.weeklySchedules,
    required this.monthlySchedules,
    required this.phoneContacts,
    required this.alertOffsetMinutes,
    required this.memberNickname,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String familyId;
  final String? familyMemberId;
  final String name;
  final DateTime startsOn;
  final DateTime endsOn;
  final EducationRecurrenceType recurrenceType;
  final List<EducationWeeklySchedule> weeklySchedules;
  final List<EducationMonthlySchedule> monthlySchedules;
  final List<EducationProgramPhoneContact> phoneContacts;
  final int? alertOffsetMinutes;
  final String memberNickname;
  final String createdAt;
  final String updatedAt;

  factory EducationProgram.fromJson(Map<String, Object?> json) {
    final familyMember = json['family_member'] as Map<String, Object?>?;
    final memberNickname = familyMember?['nickname'] as String?;
    final weeklySchedules =
        json['weekly_schedules'] as List<Object?>? ?? const [];
    final monthlySchedules =
        json['monthly_schedules'] as List<Object?>? ?? const [];
    final phoneContacts = json['phone_contacts'] as List<Object?>? ?? const [];

    return EducationProgram(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      familyMemberId: json['family_member_id'] as String?,
      name: json['name'] as String,
      startsOn: DateTime.parse(json['starts_on'] as String),
      endsOn: DateTime.parse(json['ends_on'] as String),
      recurrenceType: EducationRecurrenceType.fromJson(json['recurrence_type']),
      weeklySchedules: weeklySchedules
          .map(
            (schedule) => EducationWeeklySchedule.fromJson(
              schedule as Map<String, Object?>,
            ),
          )
          .toList(),
      monthlySchedules: monthlySchedules
          .map(
            (schedule) => EducationMonthlySchedule.fromJson(
              schedule as Map<String, Object?>,
            ),
          )
          .toList(),
      phoneContacts: phoneContacts
          .map(
            (contact) => EducationProgramPhoneContact.fromJson(
              contact as Map<String, Object?>,
            ),
          )
          .toList(),
      alertOffsetMinutes: json['alert_offset_minutes'] as int?,
      memberNickname: memberNickname ?? '담당자 없음',
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
    );
  }
}

class EducationProgramPhoneContact {
  const EducationProgramPhoneContact({
    required this.label,
    required this.phoneNumber,
  });

  final String label;
  final String phoneNumber;

  factory EducationProgramPhoneContact.fromJson(Map<String, Object?> json) {
    return EducationProgramPhoneContact(
      label: json['label'] as String? ?? '전화',
      phoneNumber: json['phoneNumber'] as String? ?? '',
    );
  }

  Map<String, Object?> toJson() {
    return {'label': label, 'phoneNumber': phoneNumber};
  }
}

class EducationWeeklySchedule {
  const EducationWeeklySchedule({
    required this.weekday,
    required this.startsAt,
    required this.endsAt,
    required this.vehicleBoardingTime,
    required this.vehicleDropoffTime,
  });

  final int weekday;
  final TimeOfDayValue startsAt;
  final TimeOfDayValue endsAt;
  final TimeOfDayValue? vehicleBoardingTime;
  final TimeOfDayValue? vehicleDropoffTime;

  factory EducationWeeklySchedule.fromJson(Map<String, Object?> json) {
    return EducationWeeklySchedule(
      weekday: json['weekday'] as int,
      startsAt: TimeOfDayValue.parse(json['startsAt'] as String),
      endsAt: TimeOfDayValue.parse(json['endsAt'] as String),
      vehicleBoardingTime: _parseOptionalTimeOfDayValue(
        json['vehicleBoardingTime'] as String?,
      ),
      vehicleDropoffTime: _parseOptionalTimeOfDayValue(
        json['vehicleDropoffTime'] as String?,
      ),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'weekday': weekday,
      'startsAt': startsAt.toApiString(),
      'endsAt': endsAt.toApiString(),
      'vehicleBoardingTime': vehicleBoardingTime?.toApiString(),
      'vehicleDropoffTime': vehicleDropoffTime?.toApiString(),
    };
  }
}

class EducationMonthlySchedule {
  const EducationMonthlySchedule({
    required this.weekOfMonth,
    required this.weekday,
    required this.dayOfMonth,
    required this.startsAt,
    required this.endsAt,
    required this.vehicleBoardingTime,
    required this.vehicleDropoffTime,
  });

  final int weekOfMonth;
  final int weekday;
  final int? dayOfMonth;
  final TimeOfDayValue startsAt;
  final TimeOfDayValue endsAt;
  final TimeOfDayValue? vehicleBoardingTime;
  final TimeOfDayValue? vehicleDropoffTime;

  factory EducationMonthlySchedule.fromJson(Map<String, Object?> json) {
    return EducationMonthlySchedule(
      weekOfMonth: json['weekOfMonth'] as int,
      weekday: json['weekday'] as int,
      dayOfMonth: json['dayOfMonth'] as int?,
      startsAt: TimeOfDayValue.parse(json['startsAt'] as String),
      endsAt: TimeOfDayValue.parse(json['endsAt'] as String),
      vehicleBoardingTime: _parseOptionalTimeOfDayValue(
        json['vehicleBoardingTime'] as String?,
      ),
      vehicleDropoffTime: _parseOptionalTimeOfDayValue(
        json['vehicleDropoffTime'] as String?,
      ),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'weekOfMonth': weekOfMonth,
      'weekday': weekday,
      'dayOfMonth': dayOfMonth,
      'startsAt': startsAt.toApiString(),
      'endsAt': endsAt.toApiString(),
      'vehicleBoardingTime': vehicleBoardingTime?.toApiString(),
      'vehicleDropoffTime': vehicleDropoffTime?.toApiString(),
    };
  }
}

class TimeOfDayValue {
  const TimeOfDayValue({required this.hour, required this.minute});

  final int hour;
  final int minute;

  factory TimeOfDayValue.parse(String value) {
    final parts = value.split(':');

    return TimeOfDayValue(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
  }

  String toApiString() => '${_twoDigits(hour)}:${_twoDigits(minute)}';
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
    required this.educationProgramId,
    required this.educationProgramName,
    required this.educationProgramPhoneContacts,
    required this.anniversaryId,
    required this.anniversaryCategory,
    required this.alertOffsetMinutes,
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
  final String? educationProgramId;
  final String? educationProgramName;
  final List<EducationProgramPhoneContact> educationProgramPhoneContacts;
  final String? anniversaryId;
  final AnniversaryCategory? anniversaryCategory;
  final int? alertOffsetMinutes;
  final String memberNickname;

  factory AppSchedule.fromJson(Map<String, Object?> json) {
    final familyMember = json['family_member'] as Map<String, Object?>?;
    final memberNickname = familyMember?['nickname'] as String?;
    final educationProgram = json['education_program'] as Map<String, Object?>?;
    final phoneContacts = educationProgram?['phone_contacts'] as List<Object?>?;
    final anniversary = json['anniversary'] as Map<String, Object?>?;

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
      educationProgramId: json['education_program_id'] as String?,
      educationProgramName: educationProgram?['name'] as String?,
      educationProgramPhoneContacts: phoneContacts == null
          ? const []
          : phoneContacts
                .map(
                  (contact) => EducationProgramPhoneContact.fromJson(
                    contact as Map<String, Object?>,
                  ),
                )
                .where((contact) => contact.phoneNumber.trim().isNotEmpty)
                .toList(),
      anniversaryId: json['anniversary_id'] as String?,
      anniversaryCategory: anniversary == null
          ? null
          : AnniversaryCategory.fromJson(anniversary['category']),
      alertOffsetMinutes: json['alert_offset_minutes'] as int?,
      memberNickname: memberNickname ?? '담당자 없음',
    );
  }
}

DateTime? _parseOptionalLocalDateTime(String? value) {
  if (value == null) {
    return null;
  }

  return DateTime.parse(value).toLocal();
}

TimeOfDayValue? _parseOptionalTimeOfDayValue(String? value) {
  if (value == null) {
    return null;
  }

  return TimeOfDayValue.parse(value.substring(0, 5));
}

String _dateOnlyString(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${_twoDigits(value.month)}-'
      '${_twoDigits(value.day)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

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
