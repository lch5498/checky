import { requireFamilyManager, requireMembership } from './families';
import { HttpError } from './http';
import { getSupabaseAdmin } from './supabase';

export type ParkingPresetType = 'building' | 'floor' | 'detail';

export type Vehicle = {
  id: string;
  family_id: string;
  nickname: string;
  plate_number: string;
  created_at: string;
  updated_at: string;
};

export type ParkingLocationPreset = {
  id: string;
  family_id: string;
  parent_preset_id: string | null;
  preset_type: ParkingPresetType;
  name: string;
  sort_order: number;
  created_at: string;
  updated_at: string;
};

export type ParkingRecord = {
  id: string;
  family_id: string;
  vehicle_id: string;
  building_preset_id: string | null;
  floor_preset_id: string | null;
  detail_preset_id: string | null;
  building_text: string;
  floor_text: string;
  detail_text: string;
  location_text: string;
  created_by_user_id: string | null;
  parked_at: string;
  created_at: string;
  updated_at: string;
  created_by_user?: {
    id: string;
    nickname: string;
  } | null;
};

type MembershipCheckOptions = {
  skipMembershipCheck?: boolean;
};

export async function getParkingDashboard(userId: string, familyId: string) {
  const membership = await requireMembership(userId, familyId);
  const [vehicles, presets, currentLocations] = await Promise.all([
    listVehicles(userId, familyId, { skipMembershipCheck: true }),
    listParkingLocationPresets(userId, familyId, {
      skipMembershipCheck: true,
    }),
    listCurrentParkingRecords(familyId),
  ]);

  return {
    canManage: membership.role === 'owner' || membership.role === 'co_owner',
    vehicles,
    presets,
    currentLocations,
  };
}

export async function listVehicles(
  userId: string,
  familyId: string,
  options: MembershipCheckOptions = {},
) {
  if (!options.skipMembershipCheck) {
    await requireMembership(userId, familyId);
  }

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('vehicles')
    .select('*')
    .eq('family_id', familyId)
    .order('created_at', { ascending: true });

  if (error) {
    throw error;
  }

  return (data ?? []) as Vehicle[];
}

export async function createVehicle(
  userId: string,
  familyId: string,
  input: { nickname: string; plateNumber: string },
) {
  await requireFamilyManager(userId, familyId);

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('vehicles')
    .insert({
      family_id: familyId,
      nickname: normalizeText(input.nickname, 'nickname', 30),
      plate_number: normalizeText(input.plateNumber, 'plate_number', 30),
    })
    .select('*')
    .single();

  if (error) {
    throw error;
  }

  return data as Vehicle;
}

export async function updateVehicle(
  userId: string,
  familyId: string,
  vehicleId: string,
  input: { nickname: string; plateNumber: string },
) {
  await requireFamilyManager(userId, familyId);

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('vehicles')
    .update({
      nickname: normalizeText(input.nickname, 'nickname', 30),
      plate_number: normalizeText(input.plateNumber, 'plate_number', 30),
    })
    .eq('id', vehicleId)
    .eq('family_id', familyId)
    .select('*')
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(404, { error: 'vehicle_not_found' });
  }

  return data as Vehicle;
}

export async function deleteVehicle(
  userId: string,
  familyId: string,
  vehicleId: string,
) {
  await requireFamilyManager(userId, familyId);

  const supabase = getSupabaseAdmin();
  const { error } = await supabase
    .from('vehicles')
    .delete()
    .eq('id', vehicleId)
    .eq('family_id', familyId);

  if (error) {
    throw error;
  }
}

export async function listParkingLocationPresets(
  userId: string,
  familyId: string,
  options: MembershipCheckOptions = {},
) {
  if (!options.skipMembershipCheck) {
    await requireMembership(userId, familyId);
  }

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('parking_location_presets')
    .select('*')
    .eq('family_id', familyId)
    .order('sort_order', { ascending: true })
    .order('created_at', { ascending: true });

  if (error) {
    throw error;
  }

  return (data ?? []) as ParkingLocationPreset[];
}

export async function createParkingLocationPreset(
  userId: string,
  familyId: string,
  input: { presetType: string; name: string; parentPresetId?: string },
) {
  await requireFamilyManager(userId, familyId);

  const presetType = normalizePresetType(input.presetType);
  const parentPresetId = await normalizeParentPresetId(
    familyId,
    presetType,
    input.parentPresetId,
  );
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('parking_location_presets')
    .insert({
      family_id: familyId,
      parent_preset_id: parentPresetId,
      preset_type: presetType,
      name: normalizeText(input.name, 'name', 40),
    })
    .select('*')
    .single();

  if (error) {
    throw error;
  }

  return data as ParkingLocationPreset;
}

export async function updateParkingLocationPreset(
  userId: string,
  familyId: string,
  presetId: string,
  input: { presetType: string; name: string; parentPresetId?: string },
) {
  await requireFamilyManager(userId, familyId);

  const presetType = normalizePresetType(input.presetType);
  const parentPresetId = await normalizeParentPresetId(
    familyId,
    presetType,
    input.parentPresetId,
  );
  if (parentPresetId === presetId) {
    throw new HttpError(400, {
      error: 'invalid_payload',
      field: 'parentPresetId',
    });
  }

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('parking_location_presets')
    .update({
      parent_preset_id: parentPresetId,
      preset_type: presetType,
      name: normalizeText(input.name, 'name', 40),
    })
    .eq('id', presetId)
    .eq('family_id', familyId)
    .select('*')
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(404, { error: 'parking_location_preset_not_found' });
  }

  return data as ParkingLocationPreset;
}

export async function deleteParkingLocationPreset(
  userId: string,
  familyId: string,
  presetId: string,
) {
  await requireFamilyManager(userId, familyId);

  const supabase = getSupabaseAdmin();
  const { error } = await supabase
    .from('parking_location_presets')
    .delete()
    .eq('id', presetId)
    .eq('family_id', familyId);

  if (error) {
    throw error;
  }
}

export async function createParkingRecord(
  userId: string,
  familyId: string,
  input: {
    vehicleId: string;
    buildingPresetId?: string;
    floorPresetId?: string;
    detailPresetId?: string;
    buildingText: string;
    floorText: string;
    detailText: string;
  },
) {
  await requireFamilyManager(userId, familyId);

  const buildingText = normalizeText(input.buildingText, 'buildingText', 40);
  const floorText = normalizeText(input.floorText, 'floorText', 40);
  const detailText = normalizeText(input.detailText, 'detailText', 40);
  const [vehicle, buildingPreset, floorPreset, detailPreset] =
    await Promise.all([
      getVehicleOrThrow(familyId, input.vehicleId),
      normalizePreset(familyId, input.buildingPresetId, 'building'),
      normalizePreset(familyId, input.floorPresetId, 'floor'),
      normalizePreset(familyId, input.detailPresetId, 'detail'),
    ]);
  validateParkingRecordPresetHierarchy(buildingPreset, floorPreset, detailPreset);

  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('parking_records')
    .insert({
      family_id: familyId,
      vehicle_id: vehicle.id,
      building_preset_id: buildingPreset?.id ?? null,
      floor_preset_id: floorPreset?.id ?? null,
      detail_preset_id: detailPreset?.id ?? null,
      building_text: buildingText,
      floor_text: floorText,
      detail_text: detailText,
      location_text: `${buildingText} / ${floorText} / ${detailText}`,
      created_by_user_id: userId,
    })
    .select(parkingRecordSelect)
    .single();

  if (error) {
    throw error;
  }

  return data as ParkingRecord;
}

async function listCurrentParkingRecords(familyId: string) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .rpc('list_current_parking_records', { target_family_id: familyId });

  if (error) {
    throw error;
  }

  return (data ?? []) as ParkingRecord[];
}

async function getVehicleOrThrow(familyId: string, vehicleId: string) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('vehicles')
    .select('*')
    .eq('id', vehicleId)
    .eq('family_id', familyId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(404, { error: 'vehicle_not_found' });
  }

  return data as Vehicle;
}

async function getPresetOrThrow(familyId: string, presetId: string) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from('parking_location_presets')
    .select('*')
    .eq('id', presetId)
    .eq('family_id', familyId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new HttpError(404, { error: 'parking_location_preset_not_found' });
  }

  return data as ParkingLocationPreset;
}

async function normalizePreset(
  familyId: string,
  presetId: string | undefined,
  presetType: ParkingPresetType,
) {
  const normalized = presetId?.trim() || null;

  if (!normalized) {
    return null;
  }

  const preset = await getPresetOrThrow(familyId, normalized);

  if (preset.preset_type !== presetType) {
    const fieldByPresetType: Record<ParkingPresetType, string> = {
      building: 'buildingPresetId',
      floor: 'floorPresetId',
      detail: 'detailPresetId',
    };

    throw new HttpError(400, {
      error: 'parking_preset_type_mismatch',
      field: fieldByPresetType[presetType],
    });
  }

  return preset;
}

async function normalizeParentPresetId(
  familyId: string,
  presetType: ParkingPresetType,
  parentPresetId: string | undefined,
) {
  if (presetType === 'building') {
    return null;
  }

  const expectedParentType: ParkingPresetType = 'building';
  const parent = await normalizePreset(
    familyId,
    parentPresetId,
    expectedParentType,
  );

  if (!parent) {
    throw new HttpError(400, {
      error: 'invalid_payload',
      field: 'parentPresetId',
    });
  }

  return parent.id;
}

function validateParkingRecordPresetHierarchy(
  buildingPreset: ParkingLocationPreset | null,
  floorPreset: ParkingLocationPreset | null,
  detailPreset: ParkingLocationPreset | null,
) {
  if (floorPreset && !buildingPreset) {
    throw new HttpError(400, {
      error: 'invalid_payload',
      field: 'buildingPresetId',
    });
  }

  if (detailPreset && !buildingPreset) {
    throw new HttpError(400, {
      error: 'invalid_payload',
      field: 'buildingPresetId',
    });
  }

  if (
    buildingPreset &&
    floorPreset &&
    floorPreset.parent_preset_id !== buildingPreset.id
  ) {
    throw new HttpError(400, {
      error: 'parking_preset_parent_mismatch',
      field: 'floorPresetId',
    });
  }

  if (
    detailPreset &&
    buildingPreset &&
    detailPreset.parent_preset_id !== buildingPreset.id
  ) {
    throw new HttpError(400, {
      error: 'parking_preset_parent_mismatch',
      field: 'detailPresetId',
    });
  }
}

function normalizePresetType(value: string): ParkingPresetType {
  if (value === 'building' || value === 'floor' || value === 'detail') {
    return value;
  }

  throw new HttpError(400, { error: 'invalid_payload', field: 'presetType' });
}

const parkingRecordSelect = `
  *,
  created_by_user:users (
    id,
    nickname
  )
`;

function normalizeText(value: string, field: string, maxLength: number) {
  const normalized = value.trim();

  if (!normalized) {
    throw new HttpError(400, { error: 'invalid_payload', field });
  }

  if (normalized.length > maxLength) {
    throw new HttpError(400, { error: 'invalid_payload', field });
  }

  return normalized;
}
