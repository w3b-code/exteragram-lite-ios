import Foundation
import UIKit
import AccountContext
import ExteraTranslation

@MainActor
func presentExteraMicrosoftConfiguration(context: AccountContext, onSaved: @escaping @MainActor () -> Void) {
    let russian = context.sharedContext.currentPresentationData.with { $0 }.strings.primaryComponent.languageCode.lowercased().hasPrefix("ru")
    func label(_ english: String, _ russianText: String) -> String { russian ? russianText : english }
    Task { @MainActor in
        let existing = await Task.detached(priority: .userInitiated) { try? ExteraMicrosoftCredentialStore.load() }.value
        let alert = UIAlertController(title: "Microsoft Azure Translator",
            message: label("Enter the key of your own Azure Translator resource. It is stored in this device's keychain. This is not your Telegram API hash.", "Введите ключ собственного ресурса Azure Translator. Он хранится в Связке ключей на этом устройстве. Это не api_hash Telegram."), preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = label("Subscription key", "Ключ подписки")
            field.text = existing?.subscriptionKey
            field.isSecureTextEntry = true
            field.textContentType = .password
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
            field.spellCheckingType = .no
        }
        alert.addTextField { field in
            field.placeholder = label("Region, if required (e.g. eastus)", "Регион, если требуется (например, eastus)")
            field.text = existing?.region
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
            field.spellCheckingType = .no
        }
        alert.addAction(UIAlertAction(title: label("Cancel", "Отмена"), style: .cancel))
        if existing != nil {
            alert.addAction(UIAlertAction(title: label("Delete key", "Удалить ключ"), style: .destructive, handler: { _ in
                Task { @MainActor in
                    do { try await Task.detached(priority: .userInitiated) { try ExteraMicrosoftCredentialStore.delete() }.value }
                    catch { presentExteraMicrosoftConfigurationError(context: context, russian: russian, invalid: false) }
                }
            }))
        }
        alert.addAction(UIAlertAction(title: label("Save and select", "Сохранить и выбрать"), style: .default, handler: { [weak alert] _ in
            guard let alert else { return }
            Task { @MainActor in
                guard let fields = alert.textFields, fields.count == 2 else { return }
                let value = ExteraMicrosoftCredentials(subscriptionKey: fields[0].text ?? "", region: fields[1].text)
                do {
                    try await Task.detached(priority: .userInitiated) { try ExteraMicrosoftCredentialStore.save(value) }.value
                    onSaved()
                } catch {
                    presentExteraMicrosoftConfigurationError(context: context, russian: russian,
                        invalid: (error as? ExteraMicrosoftCredentialStoreError) == .invalidConfiguration)
                }
            }
        }))
        context.sharedContext.applicationBindings.presentNativeController(alert)
    }
}

@MainActor
private func presentExteraMicrosoftConfigurationError(context: AccountContext, russian: Bool, invalid: Bool) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        let message: String
        if invalid {
            message = russian ? "Проверьте ключ и регион Azure Translator: внутри ключа не должно быть пробелов или переносов строк." : "Check the Azure Translator key and region. The key must not contain spaces or line breaks."
        } else {
            message = russian ? "Не удалось изменить конфигурацию в Связке ключей. Повторите после разблокировки устройства." : "Could not update the device keychain configuration. Retry after unlocking the device."
        }
        let alert = UIAlertController(title: "Microsoft", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        context.sharedContext.applicationBindings.presentNativeController(alert)
    }
}
