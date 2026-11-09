import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppStateViewModel

    @State private var sampleTestEnglish: String = "White sacrifices the exchange to create a passed pawn and put Black in zugzwang."
    @State private var sampleTestChinese: String = ""
    @State private var sampleUsedProvider: String = ""
    @State private var isTestingTranslation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("研习实时翻译引擎 (免配置·多源自动容灾)") {
                    Picker("首选免费翻译源", selection: $appState.selectedProviderRaw) {
                        ForEach(TranslationProviderType.allCases) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    Toggle("研习解说中英双语对照显示", isOn: $appState.showBilingualComments)
                    Toggle("切换着法时自动实时翻译", isOn: $appState.autoTranslateStudy)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("翻译引擎实时测试")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        TextField("测试英文棋评", text: $sampleTestEnglish)
                            .font(.caption)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            Task {
                                isTestingTranslation = true
                                let (zh, used) = await ChessTranslationService.shared.translateToChinese(
                                    text: sampleTestEnglish,
                                    preferredProvider: appState.selectedProvider
                                )
                                sampleTestChinese = zh
                                sampleUsedProvider = used.displayName
                                isTestingTranslation = false
                            }
                        } label: {
                            HStack {
                                if isTestingTranslation {
                                    ProgressView().scaleEffect(0.8)
                                }
                                Text("立即测试当前翻译源")
                            }
                        }

                        if !sampleTestChinese.isEmpty {
                            Text("译文: \(sampleTestChinese)")
                                .font(.subheadline.bold())
                                .foregroundColor(.accentColor)
                            Text("实际响应源: \(sampleUsedProvider)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("棋盘外观主题") {
                    Picker("棋盘配色", selection: $appState.boardThemeRaw) {
                        ForEach(BoardTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Lichess 账号 Token (可选·用于真人/云端AI对局)") {
                    SecureField("粘贴 Personal Access Token (lip_...)", text: $appState.apiToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Text(appState.accountRatingSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("验证并同步 Lichess 账号信息") {
                        Task { await appState.verifyTokenIfPresent() }
                    }
                }

                Section("关于 SideStore 签名与构建") {
                    LabeledContent("Bundle ID", value: "org.lichesscn.app")
                    LabeledContent("最低系统要求", value: "iOS 16.0+")
                    Text("本项目通过 GitHub Actions + XcodeGen 自动编译无签名/Ad-Hoc 伪签 IPA，可直接导入 SideStore 完成个人证书签名安装。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("设置与翻译源")
        }
    }
}
