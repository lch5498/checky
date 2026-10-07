import { createCoupon, listCoupons } from '../../../../../../src/coupons';
import { authenticateMobileRequest } from '../../../../../../src/mobile-auth';
import { jsonFromError } from '../../../../../../src/http';

export const runtime = 'nodejs';
type Context = { params: Promise<{ familyId: string }> };
export async function GET(request: Request, context: Context) {
  try {
    return Response.json(await listCoupons(authenticateMobileRequest(request), (await context.params).familyId),
      { headers: { 'Cache-Control': 'private, no-store' } });
  } catch (e) { return jsonFromError(e, 'coupons_fetch_failed'); }
}
export async function POST(request: Request, context: Context) {
  try {
    return Response.json(await createCoupon(authenticateMobileRequest(request), (await context.params).familyId, request), { status: 201 });
  } catch (e) { return jsonFromError(e, 'coupon_create_failed'); }
}
