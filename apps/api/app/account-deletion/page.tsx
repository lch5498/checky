import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: '체키 계정 및 데이터 삭제',
  description: '체키 앱의 계정과 관련 데이터 삭제 요청 방법을 안내합니다.',
  openGraph: {
    title: '체키 계정 및 데이터 삭제',
    description: '체키 계정 삭제와 관련 데이터 삭제 요청 방법을 안내합니다.',
    siteName: '체키',
    type: 'website',
    locale: 'ko_KR',
  },
};

const deletedData = [
  '계정 식별 정보와 로그인 연결 정보',
  '프로필 닉네임과 앱 설정',
  '그룹, 구성원, 초대 정보',
  '일정, 반복 일정, 기념일 정보',
  '차량, 주차 위치, 즐겨찾기 정보',
  '반복 일정 정보와 사용자가 입력한 전화번호',
];

export default function AccountDeletionPage() {
  return (
    <main className="support-shell">
      <section className="support-hero">
        <p className="eyebrow">계정 삭제</p>
        <h1>체키 계정 및 데이터 삭제</h1>
        <p className="description">
          체키 사용자는 언제든지 앱에서 계정과 관련 데이터를 삭제할 수 있습니다.
          삭제가 완료된 데이터는 복구할 수 없으니 진행 전 필요한 정보를 확인해
          주세요.
        </p>
        <a className="support-button" href="/support">
          지원 페이지로 이동
        </a>
      </section>

      <section className="support-section" aria-labelledby="delete-how-title">
        <div className="support-section-header">
          <p className="label">삭제 방법</p>
          <h2 id="delete-how-title">앱에서 직접 삭제하기</h2>
        </div>
        <div className="support-list">
          <article className="support-item">
            <h3>1. 체키 앱을 실행합니다</h3>
            <p>로그인 후 하단의 홈 탭에서 우측 상단 프로필 버튼을 선택합니다.</p>
          </article>
          <article className="support-item">
            <h3>2. 탈퇴하기를 선택합니다</h3>
            <p>
              프로필 화면 하단의 탈퇴하기를 누르고, 계정과 모든 데이터가 삭제되며
              복구되지 않는다는 안내를 확인합니다.
            </p>
          </article>
          <article className="support-item">
            <h3>3. 삭제 완료</h3>
            <p>
              탈퇴가 완료되면 체키 계정과 관련 데이터가 삭제되고 앱은 첫 화면으로
              돌아갑니다.
            </p>
          </article>
        </div>
      </section>

      <section className="support-section" aria-labelledby="delete-data-title">
        <div className="support-section-header">
          <p className="label">삭제 범위</p>
          <h2 id="delete-data-title">삭제되는 데이터</h2>
        </div>
        <div className="support-list">
          {deletedData.map((item) => (
            <article className="support-item" key={item}>
              <h3>{item}</h3>
              <p>계정 삭제 시 서비스 제공을 위해 저장된 해당 데이터가 함께 삭제됩니다.</p>
            </article>
          ))}
        </div>
      </section>

      <section className="support-section" aria-labelledby="delete-request-title">
        <div className="support-section-header">
          <p className="label">문의</p>
          <h2 id="delete-request-title">앱을 사용할 수 없는 경우</h2>
        </div>
        <div className="support-list">
          <article className="support-item">
            <h3>삭제 요청하기</h3>
            <p>
              앱에 접근할 수 없어 직접 탈퇴가 어려운 경우{' '}
              <a href="https://github.com/lch5498/favis/issues" rel="noreferrer" target="_blank">
                지원 문의
              </a>
              를 남겨 주세요. 계정 확인 후 삭제를 도와드립니다.
            </p>
          </article>
          <article className="support-item">
            <h3>보관되는 데이터</h3>
            <p>
              계정 삭제 후에도 법령 준수, 분쟁 대응, 보안 로그 등 꼭 필요한 기록은
              관련 법령과 서비스 운영에 필요한 기간 동안 제한적으로 보관될 수
              있습니다.
            </p>
          </article>
        </div>
      </section>
    </main>
  );
}
