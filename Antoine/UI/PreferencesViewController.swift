//
//  PreferencesViewController.swift
//  Antoine
//
//  Created by Serena on 09/01/2023
//

import UIKit
import Alderis // Lord forgive me for using a dependency
import class SwiftUI.UIHostingController

class PreferencesViewController: UIViewController {
    var tableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemBackground
        setupViews()
        
        title = .localized("Preferences")
        navigationController?.navigationBar.prefersLargeTitles = true
    }
    
    func setupViews() {
        self.tableView = UITableView(frame: .zero, style: .insetGrouped)
        
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.constraintCompletely(to: view)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        NSLog("Deinit called")
    }
}

extension PreferencesViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        // ✅ 修改：原来是5个分区，现在加了启动设置，变成6个
        return 6
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0, 1, 4, 5: // 0(刷新率), 1(启动设置), 4(鸣谢), 5(语言)
            return 1
        case 2:          // 2是后台模式
            return Preferences.backgroundMode == nil ? 1 : 2
        case 3:          // 3是颜色设置
            return MessageEvent.allCases.count + 1
        default:
            fatalError("How did we get here?")
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch (indexPath.section, indexPath.row) {
        case (0, 0):
            return makeTimerIntervalCellWithSlider()
            
        // ✅ 新增：第1个分区 (自动启动日志抓取)
        case (1, 0):
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            //cell.textLabel?.text = "每次打开时自动抓取" // 如果你想加入多语言，可以写 .localized("Auto Start on Launch")
            cell.textLabel?.text = .localized("Auto Start on Launch")
            let uiSwitch = UISwitch()
            uiSwitch.isOn = Preferences.autoStartStreaming
            uiSwitch.addAction(for: .valueChanged) {
                Preferences.autoStartStreaming = uiSwitch.isOn
            }
            cell.accessoryView = uiSwitch
            return cell
            
        case (2, 0):
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = .localized("Collect logs in background")
            cell.textLabel?.numberOfLines = 0
            
            let uiSwitch = UISwitch()
            uiSwitch.isOn = Preferences.backgroundMode != nil
            uiSwitch.addAction(for: .valueChanged) {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                
                if uiSwitch.isOn {
                    Preferences.backgroundMode = .backgroundTime(60) // minute by default
                    tableView.insertRows(at: [IndexPath(row: 1, section: 2)], with: .automatic)
                } else {
                    Preferences.backgroundMode = nil
                    tableView.deleteRows(at: [IndexPath(row: 1, section: 2)], with: .automatic)
                }
            }
            
            cell.accessoryView = uiSwitch
            return cell
            
        case (2, 1):
            let cell = UITableViewCell()
            let label = UILabel()
            label.text = .localized("Stay active in background for..")
            label.numberOfLines = 0
            
            let button = makeBackgroundModeSelectionButton()
            let stackView = UIStackView(arrangedSubviews: [label, button])
            stackView.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(stackView)
            
            stackView.constraintCompletely(to: cell.contentView.layoutMarginsGuide)
            return cell
            
        case (3, _):
            let cell = UITableViewCell()
            if indexPath.row == MessageEvent.allCases.count { // Reset button
                cell.textLabel?.text = .localized("Reset")
                cell.textLabel?.textColor = .systemBlue
            } else {
                let item = MessageEvent.allCasesNonLazily[indexPath.row]
                cell.textLabel?.text = item.displayText
                cell.accessoryView = colorCircleView(forColor: item.displayColor)
            }
            return cell
            
        case (4, 0):
            let cell = UITableViewCell()
            cell.textLabel?.text = .localized("Credits")
            cell.accessoryType = .disclosureIndicator
            return cell
            
        case (5, 0):
            let cell = UITableViewCell()
            cell.textLabel?.text = .localized("Language")
            cell.accessoryType = .disclosureIndicator
            return cell
            
        default:
            fatalError("What on earth happened?")
        }
    }
    
    func makeBackgroundModeSelectionButton() -> UIButton {
        let button = UIButton(type: .roundedRect)
        button.translatesAutoresizingMaskIntoConstraints = false
        let item = Preferences.backgroundMode!
        button.setTitle(item.description, for: .normal)
        MenuItem.setup(items: backgroundModeMenuItems(currentItem: item, button: button),
                       forButton: button) { [unowned self] alert in
            present(alert, animated: true)
        }
        return button
    }
    
    func backgroundModeMenuItems(currentItem: BackgroundMode, button: UIButton) -> [MenuItem] {
        let all: [BackgroundMode] = [
            .backgroundTime(60),
            .backgroundTime(5 * 60),
            .indefinitely
        ]
        
        return all.map { mode in
            return MenuItem(title: mode.description, image: nil, isEnabled: mode == currentItem) { [unowned self] in
                Preferences.backgroundMode = mode
                button.setTitle(mode.description, for: .normal)
                MenuItem.setup(items: backgroundModeMenuItems(currentItem: mode, button: button), forButton: button) { [unowned self] alert in
                    present(alert, animated: true)
                }
            }
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return .localized("Refresh Rate")
        case 1: return "Startup Options"
        case 2: return .localized("Background Mode")
        case 3: return .localized("Type Colors")
        case 4: return .localized("Credits")
        case 5: return .localized("Language")
        default: return nil
        }
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0: return .localized("RefreshRateExplaination")
        case 2: return .localized("Antoine needs Always-On Location Authorization in order to enable Background Mode")
        default: return nil
        }
    }
    
    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        switch indexPath.section {
        case 3, 4, 5:
            return true
        default:
            return false
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch indexPath.section {
        case 3:
            colorSectionItemTapped(row: indexPath.row)
        case 4:
            navigationController?.pushViewController(UIHostingController(rootView: CreditsView()), animated: true)
        case 5:
            navigationController?.pushViewController(PreferredLanguageViewController(style: .insetGrouped), animated: true)
        default:
            break
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

extension PreferencesViewController {
    func makeTimerIntervalCellWithSlider() -> UITableViewCell {
        let cell = UITableViewCell()
        let slider = UISlider()
        slider.isContinuous = true
        slider.minimumValue = 0.5
        slider.maximumValue = 10
        slider.value = Float(Preferences.streamVCTimerInterval)
        
        let currentSliderValueLabel = UILabel(text: String(format: "%.2f", slider.value), font: nil, textColor: .secondaryLabel)
        
        slider.addAction(for: .valueChanged) {
            slider.value = roundf(slider.value * 2.0) * 0.5
            currentSliderValueLabel.text = String(format: "%.2f", slider.value)
            
            if !slider.isTracking {
                Preferences.streamVCTimerInterval = Double(slider.value)
            }
        }
        
        let stackView = UIStackView(arrangedSubviews: [
            currentSliderValueLabel,
            slider,
            UILabel(text: slider.maximumValue.description, font: nil, textColor: .secondaryLabel)
        ])
        
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.spacing = 6
        
        cell.contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
            stackView.centerYAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.centerYAnchor)
        ])
        
        return cell
    }
    
    func colorCircleView(forColor color: UIColor?) -> UIView {
        let colorPreview = UIView(frame: CGRect(x: 0, y: 0, width: 29, height: 29))
        colorPreview.backgroundColor = color ?? .label
        colorPreview.layer.cornerRadius = colorPreview.frame.size.width / 2
        colorPreview.layer.borderWidth = 1.5
        colorPreview.layer.borderColor = UIColor.systemGray.cgColor
        
        return colorPreview
    }
    
    func colorSectionItemTapped(row: Int) {
        // "Reset" button
        if row == MessageEvent.allCases.count {
            CodableColor.defaultMessageEvent = nil
            MessageEvent.default.displayColor = nil
            
            CodableColor.debugMessageEvent = CodableColor(uiColor: .systemYellow)
            MessageEvent.debug.displayColor = .systemYellow
            
            CodableColor.infoMessageEvent = nil
            MessageEvent.info.displayColor = nil
            
            CodableColor.faultMessageEvent = CodableColor(uiColor: .systemRed)
            MessageEvent.fault.displayColor = .systemRed
            
            CodableColor.errorMessageEvent = CodableColor(uiColor: .systemRed)
            MessageEvent.error.displayColor = .systemRed
            
            tableView.reloadSections([3], with: .middle)
            return
        }
        
        // Setting the color of a specified type
        let vc: UIViewController
        if #available(iOS 14, *) {
            let pickerVC = UIColorPickerViewController()
            pickerVC.delegate = self
            vc = pickerVC
        } else {
            let conf = ColorPickerConfiguration(color: MessageEvent.allCases[row].displayColor ?? .label)
            let pickerVC = ColorPickerViewController(configuration: conf)
            pickerVC.delegate = self
            if UIDevice.current.userInterfaceIdiom == .pad {
                pickerVC.popoverPresentationController?.sourceView = self.navigationController?.view
            }
            
            pickerVC.modalPresentationStyle = .overFullScreen
            vc = pickerVC
        }
        
        present(vc, animated: true) {
            vc.view.tag = row
        }
    }
}

// Delegate conformance for color picker view controllers
extension PreferencesViewController: UIColorPickerViewControllerDelegate, ColorPickerDelegate {
    @available(iOS 14.0, *)
    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        setPreferredColor(viewController.selectedColor, withTag: viewController.view.tag)
    }
    
    func colorPicker(_ colorPicker: ColorPickerViewController, didAccept color: UIColor) {
        setPreferredColor(color, withTag: colorPicker.view.tag)
    }
    
    func setPreferredColor(_ color: UIColor, withTag tag: Int) {
        switch tag {
        case 0:
            CodableColor.defaultMessageEvent = CodableColor(uiColor: color)
            MessageEvent.default.displayColor = color
        case 1:
            CodableColor.infoMessageEvent = CodableColor(uiColor: color)
            MessageEvent.info.displayColor = color
        case 2:
            CodableColor.debugMessageEvent = CodableColor(uiColor: color)
            MessageEvent.debug.displayColor = color
        case 3:
            CodableColor.faultMessageEvent = CodableColor(uiColor: color)
            MessageEvent.fault.displayColor = color
        case 4:
            CodableColor.errorMessageEvent = CodableColor(uiColor: color)
            MessageEvent.error.displayColor = color
        default:
            break
        }
        
        tableView.reloadSections([3], with: .fade)
    }
}
