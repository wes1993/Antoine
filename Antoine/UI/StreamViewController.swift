//
//  StreamViewController.swift
//  Antoine
//
//  Created by Serena on 25/11/2022
//

import UIKit
import ActivityStreamBridge
import os.log

/// A View Controller displaying Log Entires / Log Messages
/// that are reported by the OS in real time.
class StreamViewController: UIViewController {
    enum Section {
        case main
    }
    
    typealias DataSource = UICollectionViewDiffableDataSource<Section, StreamEntry>
    var dataSource: DataSource!
    var collectionView: UICollectionView!
    var amountOfItemsLabel: UILabel!
    var currentlyShownEntryViewController: EntryViewController?
    
    // 标记是否已经加载过一次，防止从设置页返回时重复触发
    var hasAppearedOnce = false
    
    // 保存抓取到的所有日志，用于全局搜索
    var allEntries: [StreamEntry] = []
    
    // 判断当前是否正在搜索
    var isSearching: Bool {
        return searchController.isActive && !(searchController.searchBar.text?.isEmpty ?? true)
    }
    
    // 搜索控制器配置
    lazy var searchController: UISearchController = {
        let sc = UISearchController(searchResultsController: nil)
        sc.searchResultsUpdater = self
        sc.obscuresBackgroundDuringPresentation = false
        sc.searchBar.placeholder = .localized("Search Logs...")
        //sc.searchBar.placeholder = .localized("日志搜索...")
        return sc
    }()
    
    var filter: EntryFilter? = Preferences.entryFilter {
        didSet {
            Preferences.entryFilter = filter
        }
    }
    
    lazy var scrollDownBarButtonItem = {
        let item = UIBarButtonItem(image: UIImage(systemName: "chevron.down"),
                                   style: .plain,
                                   target: self,
                                   action: #selector(scrollAllTheWayDown))
        item.isEnabled = false
        return item
    }()
    
    lazy var playPauseButtonItem = {
        return UIBarButtonItem(image: UIImage(systemName: "pause.fill"),
                               style: .plain, target: self,
                               action: #selector(stopOrStartStream))
    }()
    
    var options: StreamOption = StreamOption(rawValue: UserDefaults.standard.integer(forKey: "StreamOptionsRawValue")) {
        didSet {
            UserDefaults.standard.set(options.rawValue, forKey: "StreamOptionsRawValue")
            if logStream.isStreaming {
                logStream.cancel()
                logStream.start(options: options)
            }
        }
    }
    
    lazy var logStream: ActivityStream = {
        let stream = ActivityStream()
        stream.delegate = self
        return stream
    }()
    
    var automaticallyScrollToBottom: Bool = true
    
    let numberFormatter: NumberFormatter = {
        let fmt = NumberFormatter()
        fmt.usesGroupingSeparator = true
        fmt.numberStyle = .decimal
        return fmt
    }()
    
    /// 缓存新进来的日志
    var batch: [StreamEntry] = []
    
    // ✅ 新增：互斥锁，用于保护 batch 数组的多线程读写安全
    let batchLock = NSLock()
    
    lazy var timer = makeTimer()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationController?.setToolbarHidden(false, animated: true)
        
        let streamTitleLabel = UILabel(text: .localized("Stream"))
        streamTitleLabel.textAlignment = .center
        streamTitleLabel.font = (navigationController?.navigationBar.value(forKey: "_defaultTitleFont") as? UIFont) ?? .boldSystemFont(ofSize: 17)
        amountOfItemsLabel = UILabel()
        amountOfItemsLabel.font = .preferredFont(forTextStyle: .caption2)
        amountOfItemsLabel.textAlignment = .center
        
        let titleStackView = UIStackView(arrangedSubviews: [streamTitleLabel, amountOfItemsLabel])
        titleStackView.axis = .vertical
        navigationItem.titleView = titleStackView
        
        setupCollectionView()
        makeDataSource()
        setToolbarItems()
        
        RunLoop.current.add(timer, forMode: .common)
        
        navigationItem.rightBarButtonItems = [
            makeShareAllBarButtonItem(),
            makePreferencesBarButtonItem()
        ]
        navigationItem.leftBarButtonItem = makeOptionsEditBarButtonItem()
        
        splitViewController?.presentsWithGesture = false
        splitViewController?.preferredDisplayMode = .allVisible
        
        NotificationCenter.default.addObserver(forName: .streamTimerIntervalDidChange,
                                               object: nil,
                                               queue: nil) { notif in
            guard let newTimerInterval = notif.object as? TimeInterval else {
                fatalError("SHOULD NOT HAVE GOTTEN HERE!! SANITY CHECK, NOW!")
            }
            
            self.timer.invalidate()
            self.timer = self.makeTimer(interval: newTimerInterval)
            RunLoop.main.add(self.timer, forMode: .common)
        }
        
        ActivityStream.enableShowPrivateData(Preferences.showPrivateData)
        
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        self.definesPresentationContext = true
    }
        
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if !hasAppearedOnce {
            hasAppearedOnce = true
            if Preferences.autoStartStreaming {
                logStream.start(options: options)
            } else {
                playPauseButtonItem.image = UIImage(systemName: "play.fill")
            }
        }
    }
    
    @objc
    func presentSettingsVC() {
        present(UINavigationController(rootViewController: PreferencesViewController(nibName: nil, bundle: nil)), animated: true)
    }
    
    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        if let presented = presentedViewController {
            if presented is UISearchController {
                presented.present(viewControllerToPresent, animated: flag, completion: completion)
            } else {
                presented.dismiss(animated: flag) {
                    super.present(viewControllerToPresent, animated: flag, completion: completion)
                }
            }
        } else {
            super.present(viewControllerToPresent, animated: flag, completion: completion)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension StreamViewController: EntryFilterViewControllerDelegate {
    @objc
    func presentFilterVC() {
        let filterVC = EntryFilterViewController(filter: filter)
        filterVC.delegate = self
        let vc = UINavigationController(rootViewController: filterVC)
        present(vc, animated: true)
    }
    
    func didFinishEditing(_ controller: EntryFilterViewController) {
        filter = controller.filter
    }
}

extension StreamViewController {
    @objc func scrollAllTheWayDown() {
        collectionView.scrollToItem(at: IndexPath(row: dataSource.snapshot().numberOfItems - 1, section: 0),
                                    at: .bottom,
                                    animated: true)
        scrollDownBarButtonItem.isEnabled = false
        automaticallyScrollToBottom = true
    }
    
    @objc func stopOrStartStream() {
        let isStreaming = logStream.isStreaming
        playPauseButtonItem.image = UIImage(systemName: isStreaming ? "play.fill" : "pause.fill")
        isStreaming ? logStream.cancel() : logStream.start(options: options)
    }
    
    private func titledStreamOptionsToMenuItems() -> [MenuItem] {
        return TitledStreamOption.all.map { opt in
            return MenuItem(title: opt.title, image: nil, isEnabled: options.contains(opt.option)) { [self] in
                options.removeOrInsertBasedOnExistance(opt.option)
                navigationItem.leftBarButtonItem = makeOptionsEditBarButtonItem()
            }
        } + [makeToggleShowPrivateMenuItem()]
    }
    
    private func makeToggleShowPrivateMenuItem() -> MenuItem {
        return MenuItem(title: .localized("Show Private data in most Logs (gets rid of <private>)"), image: nil, isEnabled: Preferences.showPrivateData) { [self] in
            var newValue = Preferences.showPrivateData
            newValue.toggle()
            ActivityStream.enableShowPrivateData(newValue)
            Preferences.showPrivateData = newValue
            navigationItem.leftBarButtonItem = makeOptionsEditBarButtonItem()
        }
    }
    
    @objc
    private func presentActionSheetForStreanOptions() {
        let alert = UIAlertController(title: .localized("Stream Options"), message: nil, preferredStyle: .actionSheet)
        for item in titledStreamOptionsToMenuItems() {
            alert.addAction(item.uiAlertAction)
        }
        alert.addAction(UIAlertAction(title: .localized("Cancel"), style: .cancel))
        present(alert, animated: true)
    }
    
    func makeOptionsEditBarButtonItem() -> UIBarButtonItem {
        if #available(iOS 14.0, *) {
            let actions = titledStreamOptionsToMenuItems()
            return UIBarButtonItem(
                image: UIImage(systemName: "list.bullet.rectangle"),
                menu: MenuItem.makeMenu(title: .localized("Stream Options"), for: actions)
            )
        }
        return UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: self, action: #selector(presentActionSheetForStreanOptions))
    }
    
        func makeToolbarItems() -> [UIBarButtonItem] {
        var items: [UIBarButtonItem] = [
            UIBarButtonItem(barButtonSystemItem: .search, target: self, action: #selector(presentFilterVC)),
            .space(.flexible),
            playPauseButtonItem,
            .space(.flexible),
            scrollDownBarButtonItem,
            .space(.flexible),
            UIBarButtonItem(image: UIImage(systemName: "xmark.circle"),
                            style: .done, target: self,
                            action: #selector(clearAll))
        ]
        
        if searchController.isActive {
            items.append(.space(.flexible))
            
            // ✅ 修复 iOS 14 无法显示该分享图标的问题
            let shareImageName: String
            if #available(iOS 15.0, *) {
                shareImageName = "square.and.arrow.up.circle" // iOS 15+ 使用带圈版本
            } else {
                shareImageName = "square.and.arrow.up.fill"   // iOS 14 降级使用实心版本
            }
            
            items.append(UIBarButtonItem(image: UIImage(systemName: shareImageName),
                                         style: .plain, target: self,
                                         action: #selector(shareSearchedLogs)))
        }
        
        return items
    }
 
    func makeShareAllBarButtonItem() -> UIBarButtonItem {
        return UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"),
                               style: .plain,
                               target: self,
                               action: #selector(shareAllLogs))
    }
    
    @objc
    func shareAllLogs() {
        let bounds: CGRect = view.bounds
        exportAll(entries: allEntries,
                  senderView: view,
                  senderRect: CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0))
    }
    
    @objc
    func shareSearchedLogs() {
        let searchedEntries = dataSource.snapshot().itemIdentifiers
        let bounds: CGRect = view.bounds
        exportAll(entries: searchedEntries,
                  senderView: view,
                  senderRect: CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0))
    }
    
    func makePreferencesBarButtonItem() -> UIBarButtonItem {
        return UIBarButtonItem(image: UIImage(systemName: "gear"),
                        style: .plain, target: self,
                        action: #selector(presentSettingsVC))
    }
    
    func setToolbarItems() {
        setToolbarItems(makeToolbarItems(), animated: true)
    }
    
    @objc
    func clearAll() {
        allEntries.removeAll()
        
        // 清空时也加锁，防止数据混乱
        batchLock.lock()
        batch.removeAll()
        batchLock.unlock()
        
        var snapshot: NSDiffableDataSourceSnapshot<Section, StreamEntry> = .init()
        snapshot.appendSections([.main])
        dataSourceApply(snapshot: snapshot)
    }
    
    func dataSourceApply(snapshot: NSDiffableDataSourceSnapshot<Section, StreamEntry>) {
        dataSource.apply(snapshot) {
            self.amountOfItemsLabel.text = .localized("%@ Logs", arguments: self.numberFormatter.string(from: snapshot.numberOfItems as NSNumber) ?? snapshot.numberOfItems.description)
        }
    }
    
    func makeTimer(interval: TimeInterval = Preferences.streamVCTimerInterval) -> Timer {
        return Timer(timeInterval: interval, repeats: true) { [self] _ in
            guard logStream.isStreaming,
                    UIApplication.shared.applicationState != .background else {
                return
            }
            
            addBatch()
            if automaticallyScrollToBottom {
                scrollAllTheWayDown()
            }
        }
    }
    
    func addBatch() {
        // ✅ 修改：从缓存池安全地提取出这一批次的所有日志，并立刻清空原缓存池
        batchLock.lock()
        let currentBatch = batch
        batch = []
        batchLock.unlock()
        
        guard !currentBatch.isEmpty else { return }
        
        allEntries.append(contentsOf: currentBatch)
        
        var snapshot = dataSource.snapshot()
        
        if isSearching, let searchText = searchController.searchBar.text?.lowercased() {
            let filteredBatch = currentBatch.filter { entry in
                entry.eventMessage.lowercased().contains(searchText) ||
                entry.process.lowercased().contains(searchText) ||
                (entry.subsystem?.lowercased().contains(searchText) ?? false) ||
                (entry.category?.lowercased().contains(searchText) ?? false)
            }
            if !filteredBatch.isEmpty {
                snapshot.appendItems(filteredBatch)
            }
        } else {
            snapshot.appendItems(currentBatch)
        }
        
        dataSourceApply(snapshot: snapshot)
    }
}

extension StreamViewController: UICollectionViewDelegate {
    func setupCollectionView() {
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        
        collectionView.constraintCompletely(to: view)
        collectionView.backgroundColor = .secondarySystemBackground
        collectionView.delegate = self
        
        collectionView.register(EntryCollectionViewCell.self,
                                forCellWithReuseIdentifier: EntryCollectionViewCell.reuseIdentifier)
    }
    
    func makeLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                              heightDimension: .fractionalHeight(1.0))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                               heightDimension: .absolute(75))
        
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitem: item, count: 1)
        let spacing = CGFloat(10)
        group.interItemSpacing = .fixed(spacing)
        
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = spacing
        section.contentInsets = NSDirectionalEdgeInsets(top: 0,
                                                        leading: spacing,
                                                        bottom: 0,
                                                        trailing: spacing)
        return UICollectionViewCompositionalLayout(section: section)
    }
    
    func makeDataSource() {
        if #available(iOS 14.0, *), getenv("ANTOINE_DATA_SOURCE_NO_CELL_REGISTRATION") == nil {
            let cellRegistration = UICollectionView.CellRegistration<EntryCollectionViewCell, StreamEntry> { cell, indexPath, itemIdentifier in
                cell.configure(message: itemIdentifier)
            }
            
            dataSource = DataSource(collectionView: collectionView) { collectionView, indexPath, itemIdentifier in
                return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: itemIdentifier)
            }
        } else {
            dataSource = DataSource(collectionView: collectionView) { collectionView, indexPath, itemIdentifier in
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EntryCollectionViewCell.reuseIdentifier, for: indexPath) as! EntryCollectionViewCell
                cell.configure(message: itemIdentifier)
                return cell
            }
        }
        
        var snapshot = dataSource.snapshot()
        snapshot.appendSections([.main])
        dataSourceApply(snapshot: snapshot)
    }
    
    func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        scrollDownBarButtonItem.isEnabled = true
        automaticallyScrollToBottom = false
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        scrollDownBarButtonItem.isEnabled = true
        automaticallyScrollToBottom = false
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        presentEntryViewController(for: item)
    }
    
    func presentEntryViewController(_ controller: EntryViewController) {
        if #available(iOS 14, *), let splitViewController, Preferences.useiPadMode {
            if splitViewController.viewController(for: .secondary) is EntryViewController {
                splitViewController.setViewController(nil, for: .secondary)
            }
            
            if splitViewController.viewController(for: .primary) != self {
                splitViewController.setViewController(self, for: .primary)
            }
            currentlyShownEntryViewController = controller
            splitViewController.setViewController(currentlyShownEntryViewController, for: .secondary)
        } else {
            let vc = UINavigationController(rootViewController: controller)
            
            if #available(iOS 15.0, *), UIDevice.current.userInterfaceIdiom == .pad,
               let sheet = vc.sheetPresentationController {
                sheet.prefersGrabberVisible = true
                sheet.detents = [.medium(), .large()]
                sheet.preferredCornerRadius = 20
            }
            
            present(vc, animated: true)
        }
    }
    
    func presentEntryViewController(for entry: StreamEntry) {
        presentEntryViewController(EntryViewController(entry: entry))
    }
    
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let entry = dataSource.itemIdentifier(for: indexPath) else {
            return nil
        }
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: {
            return EntryViewController(entry: entry)
        }, actionProvider: { _ in
            func _makeCopyUIAction(title: String, stringToCopy: String) -> UIAction {
                return UIAction(title: title) { _ in
                    UIPasteboard.general.string = stringToCopy
                }
            }
            
            let copyName = _makeCopyUIAction(title: "Process Name", stringToCopy: entry.process)
            let copyPath = _makeCopyUIAction(title: "Process Path", stringToCopy: entry.processImagePath)
            let copyMessage = _makeCopyUIAction(title: "Message", stringToCopy: entry.eventMessage)
            let embeddedCopyMenu = UIMenu(title: "Copy..",
                                          image: UIImage(systemName: "doc.on.doc"),
                                          children: [copyName, copyMessage, copyPath])
            let shareAction = UIAction(title: .localized("Share Log"), image: UIImage(systemName: "square.and.arrow.up")) { [unowned self] _ in
                let bounds: CGRect = view.bounds
                export(entry: entry, senderView: view, senderRect: CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0))
            }
            
            return UIMenu(children: [embeddedCopyMenu, shareAction])
        })
    }
    
    func collectionView(_ collectionView: UICollectionView, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
        guard let vc = animator.previewViewController as? EntryViewController else { return }
        presentEntryViewController(vc)
    }
}

extension StreamViewController: ActivityStreamDelegate {
    func activityStream(streamEventDidChangeTo newEvent: StreamEvent?) {
        DispatchQueue.main.async {
            self.playPauseButtonItem.image = UIImage(systemName: self.logStream.isStreaming ? "pause.fill" : "play.fill")
        }
    }
    
    func activityStream(didRecieveEntry entryPointer: os_activity_stream_entry_t, error: CInt) {
        let entry = StreamEntry(entry: entryPointer)
        if filter?.entryPassesFilter(entry) ?? true {
            // ✅ 修改：使用互斥锁来保证数组追加的绝对安全。不阻塞主线程，也不丢日志！
            batchLock.lock()
            batch.append(entry)
            batchLock.unlock()
        }
    }
}

// 遵循 UISearchResultsUpdating 协议处理搜索回调
extension StreamViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, StreamEntry>()
        snapshot.appendSections([.main])
        
        if isSearching, let searchText = searchController.searchBar.text?.lowercased() {
            let filtered = allEntries.filter { entry in
                entry.eventMessage.lowercased().contains(searchText) ||
                entry.process.lowercased().contains(searchText) ||
                (entry.subsystem?.lowercased().contains(searchText) ?? false) ||
                (entry.category?.lowercased().contains(searchText) ?? false)
            }
            snapshot.appendItems(filtered)
        } else {
            snapshot.appendItems(allEntries)
        }
        
        dataSourceApply(snapshot: snapshot)
        setToolbarItems()
    }
}
