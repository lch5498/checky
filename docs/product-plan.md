# 제품 계획

## MVP 목표

그룹 내 반복 일정과 주차 위치를 빠르게 확인하고 기록하는 작은 내부 앱을 만든다. 첫 화면은 복잡한 대시보드 없이 두 개의 큰 메뉴 버튼만 제공한다.

## 화면

### 홈

- `일정 관리` 버튼
- `주차 관리` 버튼

### 반복 일정 관리

- 이번 주 반복 일정 목록
- 일정 추가: 학생 이름, 반복 일정명, 시작 시간, 종료 시간, 메모
- 일정 수정/삭제
- 다음 단계: 반복 일정, 알림, 캘린더 연동

### 주차 관리

- 현재 주차 위치 보기
- 주차 위치 등록: 차량명, 위치, 주차 시간, 메모
- 이전 주차 기록 보기
- 다음 단계: 사진 첨부, 지도 링크, 위치 공유

## 데이터 모델

- `family_members`: 그룹 구성원
- `academy_events`: 반복 일정
- `parking_records`: 주차 기록

## 기술 방향

- Flutter 앱은 iOS 우선으로 개발한다.
- 앱은 Vercel API만 호출한다.
- Vercel API는 Supabase service role key를 서버에서만 사용한다.
- Supabase Row Level Security는 켜고, 클라이언트 직접 접근은 나중에 인증을 붙일 때 정책을 확장한다.

## 개발 마일스톤

1. 모노레포 생성, Flutter iOS 앱 기본 홈, Vercel API skeleton, Supabase migration
2. 반복 일정 CRUD API와 앱 목록/추가 화면
3. 주차 기록 API와 앱 현재 위치/등록 화면
4. 그룹용 간단 인증 또는 초대 방식 결정
5. iOS TestFlight 배포 준비
