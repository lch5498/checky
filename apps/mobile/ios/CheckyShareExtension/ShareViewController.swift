import Security
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController, UITextViewDelegate {
  private let contentTextView = UITextView()
  private let familyButton = UIButton(type: .system)
  private let channelButton = UIButton(type: .system)
  private let saveButton = UIButton(type: .system)
  private let statusLabel = UILabel()
  private let activityIndicator = UIActivityIndicatorView(style: .medium)

  private var didStart = false
  private var apiClient: ShareAPIClient?
  private var families: [ShareFamily] = []
  private var channels: [ShareChannel] = []
  private var selectedFamily: ShareFamily?
  private var selectedChannel: ShareChannel?
  private var channelRequestId: UUID?
  private var isSaving = false

  override func viewDidLoad() {
    super.viewDidLoad()
    preferredContentSize = CGSize(width: 420, height: 560)
    configureView()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    guard !didStart else { return }
    didStart = true
    beginLoading()
  }

  private func configureView() {
    view.backgroundColor = UIColor(red: 0.94, green: 0.99, blue: 0.98, alpha: 1)

    let cancelButton = UIButton(type: .system)
    cancelButton.setTitle("취소", for: .normal)
    cancelButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
    cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)

    let titleLabel = UILabel()
    titleLabel.text = "체키에 스크랩"
    titleLabel.textAlignment = .center
    titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
    titleLabel.textColor = UIColor(red: 0.05, green: 0.15, blue: 0.14, alpha: 1)

    saveButton.setTitle("저장", for: .normal)
    saveButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
    saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)
    saveButton.isEnabled = false

    let navigationRow = UIStackView(arrangedSubviews: [cancelButton, titleLabel, saveButton])
    navigationRow.axis = .horizontal
    navigationRow.alignment = .center
    navigationRow.distribution = .fill
    cancelButton.widthAnchor.constraint(equalToConstant: 54).isActive = true
    saveButton.widthAnchor.constraint(equalToConstant: 54).isActive = true

    contentTextView.delegate = self
    contentTextView.font = .systemFont(ofSize: 15)
    contentTextView.textColor = UIColor(red: 0.08, green: 0.16, blue: 0.15, alpha: 1)
    contentTextView.backgroundColor = .white
    contentTextView.layer.cornerRadius = 12
    contentTextView.layer.borderWidth = 1
    contentTextView.layer.borderColor = UIColor(red: 0.79, green: 0.90, blue: 0.88, alpha: 1).cgColor
    contentTextView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
    contentTextView.heightAnchor.constraint(equalToConstant: 116).isActive = true

    configureSelectionButton(familyButton, placeholder: "그룹을 선택해 주세요")
    configureSelectionButton(channelButton, placeholder: "스크랩 채널을 선택해 주세요")

    statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
    statusLabel.textColor = UIColor(red: 0.34, green: 0.43, blue: 0.42, alpha: 1)
    statusLabel.numberOfLines = 0
    statusLabel.textAlignment = .center

    activityIndicator.color = UIColor(red: 0.08, green: 0.62, blue: 0.58, alpha: 1)
    activityIndicator.hidesWhenStopped = true

    let statusRow = UIStackView(arrangedSubviews: [activityIndicator, statusLabel])
    statusRow.axis = .horizontal
    statusRow.alignment = .center
    statusRow.spacing = 8

    let stack = UIStackView(arrangedSubviews: [
      navigationRow,
      divider(),
      sectionLabel("공유한 내용"),
      contentTextView,
      sectionLabel("그룹"),
      familyButton,
      sectionLabel("스크랩 채널"),
      channelButton,
      statusRow,
    ])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .vertical
    stack.spacing = 10
    stack.setCustomSpacing(14, after: navigationRow)
    stack.setCustomSpacing(18, after: contentTextView)
    stack.setCustomSpacing(18, after: familyButton)
    stack.setCustomSpacing(14, after: channelButton)

    let scrollView = UIScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.keyboardDismissMode = .interactive
    scrollView.alwaysBounceVertical = true
    view.addSubview(scrollView)
    scrollView.addSubview(stack)

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
      stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 10),
      stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 18),
      stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -18),
      stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
      stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -36),
    ])
  }

  private func configureSelectionButton(_ button: UIButton, placeholder: String) {
    var configuration = UIButton.Configuration.plain()
    configuration.title = placeholder
    configuration.image = UIImage(systemName: "chevron.up.chevron.down")
    configuration.imagePlacement = .trailing
    configuration.imagePadding = 8
    configuration.baseForegroundColor = UIColor(red: 0.08, green: 0.22, blue: 0.20, alpha: 1)
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
    button.configuration = configuration
    button.contentHorizontalAlignment = .fill
    button.backgroundColor = .white
    button.layer.cornerRadius = 11
    button.layer.borderWidth = 1
    button.layer.borderColor = UIColor(red: 0.79, green: 0.90, blue: 0.88, alpha: 1).cgColor
    button.showsMenuAsPrimaryAction = true
    button.isEnabled = false
    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true
  }

  private func sectionLabel(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = .systemFont(ofSize: 14, weight: .bold)
    label.textColor = UIColor(red: 0.18, green: 0.28, blue: 0.27, alpha: 1)
    return label
  }

  private func divider() -> UIView {
    let divider = UIView()
    divider.backgroundColor = UIColor(red: 0.79, green: 0.90, blue: 0.88, alpha: 1)
    divider.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
    return divider
  }

  private func beginLoading() {
    setLoading(true, message: "공유할 내용을 불러오는 중이에요.")
    loadSharedText { [weak self] result in
      guard let self else { return }

      switch result {
      case .success(let text):
        self.contentTextView.text = String(text.prefix(2_000))
        self.loadSessionAndFamilies()
      case .failure:
        self.setLoading(false, message: "공유할 링크나 텍스트를 찾을 수 없어요.", isError: true)
      }
    }
  }

  private func loadSessionAndFamilies() {
    guard let session = SharedSessionKeychain.readSession() else {
      setLoading(
        false,
        message: "체키 앱에서 로그인한 뒤 다시 공유해 주세요.",
        isError: true
      )
      return
    }

    guard let baseURL = URL(string: session.apiBaseUrl) else {
      setLoading(false, message: "체키 서버 설정을 확인할 수 없어요.", isError: true)
      return
    }

    let client = ShareAPIClient(baseURL: baseURL, accessToken: session.accessToken)
    apiClient = client
    setLoading(true, message: "그룹을 불러오는 중이에요.")
    client.listFamilies { [weak self] result in
      guard let self else { return }

      switch result {
      case .success(let families):
        self.families = families
        guard let family = families.first else {
          self.setLoading(false, message: "참여 중인 그룹이 없어요.", isError: true)
          return
        }
        self.configureFamilyMenu()
        self.selectFamily(family)
      case .failure(let error):
        self.showAPIError(error)
      }
    }
  }

  private func configureFamilyMenu() {
    familyButton.menu = UIMenu(
      title: "그룹 선택",
      children: families.map { family in
        UIAction(
          title: family.name,
          state: family.id == selectedFamily?.id ? .on : .off
        ) { [weak self] _ in
          self?.selectFamily(family)
        }
      }
    )
    familyButton.isEnabled = !families.isEmpty && !isSaving
  }

  private func selectFamily(_ family: ShareFamily) {
    selectedFamily = family
    selectedChannel = nil
    channels = []
    updateButtonTitle(familyButton, title: family.name)
    updateButtonTitle(channelButton, title: "채널을 불러오는 중…")
    channelButton.menu = nil
    channelButton.isEnabled = false
    configureFamilyMenu()
    updateSaveAvailability()

    let requestId = UUID()
    channelRequestId = requestId
    setLoading(true, message: "스크랩 채널을 불러오는 중이에요.")
    apiClient?.listChannels(familyId: family.id) { [weak self] result in
      guard let self, self.channelRequestId == requestId else { return }

      switch result {
      case .success(let channels):
        self.channels = channels
        if let channel = channels.first {
          self.selectedChannel = channel
          self.updateButtonTitle(self.channelButton, title: channel.name)
          self.configureChannelMenu()
          self.setLoading(false, message: nil)
        } else {
          self.updateButtonTitle(self.channelButton, title: "저장할 채널이 없어요")
          self.setLoading(
            false,
            message: "체키 앱에서 스크랩 채널을 먼저 만들어 주세요.",
            isError: true
          )
        }
        self.updateSaveAvailability()
      case .failure(let error):
        self.showAPIError(error)
      }
    }
  }

  private func configureChannelMenu() {
    channelButton.menu = UIMenu(
      title: "스크랩 채널 선택",
      children: channels.map { channel in
        UIAction(
          title: channel.name,
          state: channel.id == selectedChannel?.id ? .on : .off
        ) { [weak self] _ in
          guard let self else { return }
          self.selectedChannel = channel
          self.updateButtonTitle(self.channelButton, title: channel.name)
          self.configureChannelMenu()
          self.updateSaveAvailability()
        }
      }
    )
    channelButton.isEnabled = !channels.isEmpty && !isSaving
  }

  private func updateButtonTitle(_ button: UIButton, title: String) {
    var configuration = button.configuration
    configuration?.title = title
    button.configuration = configuration
  }

  private func updateSaveAvailability() {
    saveButton.isEnabled = !isSaving
      && selectedFamily != nil
      && selectedChannel != nil
      && !contentTextView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  @objc private func save() {
    guard
      !isSaving,
      let family = selectedFamily,
      let channel = selectedChannel,
      let apiClient
    else {
      return
    }

    let content = contentTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty else {
      setLoading(false, message: "저장할 내용을 입력해 주세요.", isError: true)
      return
    }

    isSaving = true
    contentTextView.isEditable = false
    familyButton.isEnabled = false
    channelButton.isEnabled = false
    updateSaveAvailability()
    setLoading(true, message: "스크랩에 저장하는 중이에요.")

    apiClient.createPost(
      familyId: family.id,
      channelId: channel.id,
      content: String(content.prefix(2_000))
    ) { [weak self] result in
      guard let self else { return }

      switch result {
      case .success:
        self.setLoading(false, message: "\(channel.name)에 저장했어요.", isSuccess: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
          self.extensionContext?.completeRequest(returningItems: nil)
        }
      case .failure(let error):
        self.isSaving = false
        self.contentTextView.isEditable = true
        self.configureFamilyMenu()
        self.configureChannelMenu()
        self.updateSaveAvailability()
        self.showAPIError(error)
      }
    }
  }

  @objc private func cancel() {
    extensionContext?.completeRequest(returningItems: nil)
  }

  func textViewDidChange(_ textView: UITextView) {
    if textView.text.count > 2_000 {
      textView.text = String(textView.text.prefix(2_000))
    }
    updateSaveAvailability()
  }

  private func setLoading(
    _ loading: Bool,
    message: String?,
    isError: Bool = false,
    isSuccess: Bool = false
  ) {
    if loading {
      activityIndicator.startAnimating()
    } else {
      activityIndicator.stopAnimating()
    }
    statusLabel.text = message
    if isError {
      statusLabel.textColor = UIColor(red: 0.72, green: 0.18, blue: 0.16, alpha: 1)
    } else if isSuccess {
      statusLabel.textColor = UIColor(red: 0.04, green: 0.48, blue: 0.40, alpha: 1)
    } else {
      statusLabel.textColor = UIColor(red: 0.34, green: 0.43, blue: 0.42, alpha: 1)
    }
  }

  private func showAPIError(_ error: Error) {
    let message: String
    switch error as? ShareAPIError {
    case .unauthorized:
      message = "로그인이 만료됐어요. 체키 앱에서 다시 로그인해 주세요."
    case .server(let serverMessage):
      message = serverMessage?.isEmpty == false
        ? serverMessage!
        : "스크랩을 저장할 수 없어요. 잠시 후 다시 시도해 주세요."
    default:
      message = "서버에 연결할 수 없어요. 잠시 후 다시 시도해 주세요."
    }
    setLoading(false, message: message, isError: true)
  }

  private func loadSharedText(completion: @escaping (Result<String, Error>) -> Void) {
    let providers = extensionContext?.inputItems
      .compactMap { $0 as? NSExtensionItem }
      .flatMap { $0.attachments ?? [] } ?? []
    loadSharedText(from: providers, index: 0, completion: completion)
  }

  private func loadSharedText(
    from providers: [NSItemProvider],
    index: Int,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    guard index < providers.count else {
      completion(.failure(ShareInputError.missingText))
      return
    }

    let provider = providers[index]
    if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
      provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) {
        [weak self] item, _ in
        let text = (item as? URL)?.absoluteString ?? (item as? String)
        self?.handleLoadedText(
          text,
          providers: providers,
          nextIndex: index + 1,
          completion: completion
        )
      }
      return
    }

    if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
      provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) {
        [weak self] item, _ in
        let text = (item as? String) ?? (item as? NSAttributedString)?.string
        self?.handleLoadedText(
          text,
          providers: providers,
          nextIndex: index + 1,
          completion: completion
        )
      }
      return
    }

    loadSharedText(from: providers, index: index + 1, completion: completion)
  }

  private func handleLoadedText(
    _ text: String?,
    providers: [NSItemProvider],
    nextIndex: Int,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    let normalized = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !normalized.isEmpty else {
      loadSharedText(from: providers, index: nextIndex, completion: completion)
      return
    }
    DispatchQueue.main.async {
      completion(.success(normalized))
    }
  }
}

private struct ShareFamily {
  let id: String
  let name: String
}

private struct ShareChannel {
  let id: String
  let name: String
}

private struct SharedSession {
  let accessToken: String
  let apiBaseUrl: String
}

private enum SharedSessionKeychain {
  private static let service = "checky.shared.auth"
  private static let accessGroupSuffix = "com.family.checky.mobile.shared"

  static func readSession() -> SharedSession? {
    guard
      let accessToken = read(key: "auth.accessToken"),
      !accessToken.isEmpty,
      let apiBaseUrl = read(key: "auth.apiBaseUrl"),
      !apiBaseUrl.isEmpty
    else {
      return nil
    }
    return SharedSession(accessToken: accessToken, apiBaseUrl: apiBaseUrl)
  }

  private static func read(key: String) -> String? {
    guard let accessGroup else { return nil }
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrAccount: key,
      kSecAttrService: service,
      kSecAttrAccessGroup: accessGroup,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    guard
      SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  private static var accessGroup: String? {
    let configured = Bundle.main.object(
      forInfoDictionaryKey: "CheckySharedKeychainAccessGroup"
    ) as? String
    return configured?.hasSuffix(accessGroupSuffix) == true ? configured : nil
  }
}

private final class ShareAPIClient {
  private let baseURL: URL
  private let accessToken: String

  init(baseURL: URL, accessToken: String) {
    self.baseURL = baseURL
    self.accessToken = accessToken
  }

  func listFamilies(completion: @escaping (Result<[ShareFamily], Error>) -> Void) {
    request(method: "GET", path: "/api/mobile/families") { result in
      completion(
        result.flatMap { json in
          let items = json["families"] as? [[String: Any]] ?? []
          let families = items.compactMap { item -> ShareFamily? in
            guard
              let family = item["family"] as? [String: Any],
              let id = family["id"] as? String,
              let name = family["name"] as? String
            else {
              return nil
            }
            return ShareFamily(id: id, name: name)
          }
          return .success(families)
        }
      )
    }
  }

  func listChannels(
    familyId: String,
    completion: @escaping (Result<[ShareChannel], Error>) -> Void
  ) {
    request(method: "GET", path: "/api/mobile/families/\(familyId)/scraps") { result in
      completion(
        result.flatMap { json in
          let items = json["channels"] as? [[String: Any]] ?? []
          let channels = items.compactMap { item -> ShareChannel? in
            guard
              let id = item["id"] as? String,
              let name = item["name"] as? String
            else {
              return nil
            }
            return ShareChannel(id: id, name: name)
          }
          return .success(channels)
        }
      )
    }
  }

  func createPost(
    familyId: String,
    channelId: String,
    content: String,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    request(
      method: "POST",
      path: "/api/mobile/families/\(familyId)/scraps/\(channelId)",
      body: ["content": content]
    ) { result in
      completion(result.map { _ in () })
    }
  }

  private func request(
    method: String,
    path: String,
    body: [String: Any]? = nil,
    completion: @escaping (Result<[String: Any], Error>) -> Void
  ) {
    let pathWithoutLeadingSlash = path.hasPrefix("/") ? String(path.dropFirst()) : path
    let url = baseURL.appendingPathComponent(pathWithoutLeadingSlash)
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 12
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    }

    URLSession.shared.dataTask(with: request) { data, response, error in
      let result: Result<[String: Any], Error>
      if let error {
        result = .failure(error)
      } else if let response = response as? HTTPURLResponse {
        let json = data.flatMap {
          try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        } ?? [:]
        if response.statusCode == 401 {
          result = .failure(ShareAPIError.unauthorized)
        } else if !(200..<300).contains(response.statusCode) {
          let message = (json["message"] as? String) ?? (json["error"] as? String)
          result = .failure(ShareAPIError.server(message))
        } else {
          result = .success(json)
        }
      } else {
        result = .failure(ShareAPIError.invalidResponse)
      }

      DispatchQueue.main.async {
        completion(result)
      }
    }.resume()
  }
}

private enum ShareInputError: Error {
  case missingText
}

private enum ShareAPIError: Error {
  case unauthorized
  case server(String?)
  case invalidResponse
}
