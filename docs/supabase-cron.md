# Supabase Cron 설정

체키의 일정 알림 발송은 Vercel API가 담당하고, 반복 실행 트리거는 Supabase Cron에서 호출합니다.

```text
Supabase Cron -> https://favis.vercel.app/api/cron/schedule-alerts -> FCM/APNs
```

Vercel Hobby 플랜은 분 단위 cron을 쓰기 어렵기 때문에, 매분 실행이 필요한 일정 알림은 Supabase Cron으로 구성합니다. Supabase Cron은 Postgres 기반 cron job을 만들 수 있고, `pg_net`을 사용하면 SQL에서 외부 HTTP endpoint를 호출할 수 있습니다.

참고:

- Supabase Cron: https://supabase.com/docs/guides/cron
- Supabase pg_net: https://supabase.com/docs/guides/database/extensions/pg_net

## 1. Vercel 환경변수 확인

Vercel Production 환경에 아래 환경변수가 있어야 합니다.

```text
CRON_SECRET=충분히_긴_랜덤_문자열
```

`/api/cron/schedule-alerts`는 `CRON_SECRET`이 설정되어 있으면 아래 헤더가 맞을 때만 실행됩니다.

```text
Authorization: Bearer {CRON_SECRET}
```

`CRON_SECRET`은 repo에 커밋하지 않습니다. Vercel Environment Variables와 Supabase Cron 설정에만 같은 값을 넣습니다.

## 2. Supabase Dashboard에서 설정하기

가장 추천하는 방식입니다.

1. Supabase Dashboard 접속
2. 프로젝트 선택
3. `Database > Extensions`에서 `pg_net` 활성화
4. `Integrations > Cron` 또는 `Database > Cron` 메뉴로 이동
5. 새 job 생성
6. 이름 입력

```text
favis-schedule-alerts-every-minute
```

7. 스케줄 입력

```text
* * * * *
```

8. 실행 SQL 입력

```sql
select net.http_get(
  url := 'https://favis.vercel.app/api/cron/schedule-alerts',
  headers := jsonb_build_object(
    'Authorization', 'Bearer 여기에_CRON_SECRET_값'
  ),
  timeout_milliseconds := 10000
);
```

9. 저장 후 다음 분에 실행되는지 확인

## 3. SQL Editor에서 설정하기

Dashboard UI 대신 SQL Editor에서 직접 설정할 수도 있습니다.

```sql
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;

select cron.unschedule('favis-schedule-alerts-every-minute')
where exists (
  select 1
  from cron.job
  where jobname = 'favis-schedule-alerts-every-minute'
);

select cron.schedule(
  'favis-schedule-alerts-every-minute',
  '* * * * *',
  $$
  select net.http_get(
    url := 'https://favis.vercel.app/api/cron/schedule-alerts',
    headers := jsonb_build_object(
      'Authorization', 'Bearer 여기에_CRON_SECRET_값'
    ),
    timeout_milliseconds := 10000
  );
  $$
);
```

주의: 위 SQL에는 실제 `CRON_SECRET` 값이 들어가므로 migration 파일로 커밋하지 않습니다. 운영 Supabase SQL Editor에서만 실행합니다.

## 4. 수동 테스트

Vercel API가 정상인지 먼저 로컬에서 확인합니다.

```bash
curl -X GET https://favis.vercel.app/api/cron/schedule-alerts \
  -H "Authorization: Bearer 여기에_CRON_SECRET_값"
```

정상 응답 예시는 아래와 비슷합니다.

```json
{
  "ok": true,
  "windowStart": "2026-07-05T00:00:00.000Z",
  "windowEnd": "2026-07-05T00:05:00.000Z",
  "dueScheduleCount": 0,
  "claimedScheduleCount": 0,
  "sentScheduleCount": 0,
  "tokenCount": 0,
  "successCount": 0,
  "failureCount": 0,
  "schedules": []
}
```

Supabase에서 HTTP 호출 결과를 확인하려면 SQL Editor에서 아래 쿼리를 실행합니다.

```sql
select *
from net._http_response
order by created desc
limit 20;
```

Cron 실행 이력은 아래에서 확인합니다.

```sql
select *
from cron.job_run_details
where jobid in (
  select jobid
  from cron.job
  where jobname = 'favis-schedule-alerts-every-minute'
)
order by start_time desc
limit 20;
```

## 5. 운영 메모

- API는 기본적으로 최근 5분 사이 `alert_due_at`이 지난 일정만 조회합니다.
- 중복 발송 방지는 `schedule_alert_deliveries`의 `(schedule_id, alert_due_at)` unique 제약으로 처리합니다.
- Supabase Cron이 잠시 늦게 호출되어도 5분 lookback 안에서는 발송됩니다.
- lookback은 Vercel 환경변수 `SCHEDULE_ALERT_LOOKBACK_MINUTES`로 조정할 수 있습니다.
- 푸시 제목은 `{가족이름} - {일정제목}` 형식입니다.
- 푸시 본문은 `정시`, `10분전`, `1시간전`, `1일전` 형식입니다.
