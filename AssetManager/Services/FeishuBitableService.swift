import Foundation
import SwiftUI
import Combine
import CryptoKit

/// 飞书多维表格服务 - 通过 API 同步资产数据到飞书多维表格
@MainActor
class FeishuBitableService: ObservableObject {
    @Published var appId: String = ""
    @Published var appSecret: String = ""
    @Published var assetAppToken: String = ""
    @Published var recordAppToken: String = ""
    @Published var assetTableId: String = ""
    @Published var recordTableId: String = ""
    @Published var accessToken: String = ""
    @Published var isConfigured: Bool = false
    @Published var isSyncing: Bool = false
    @Published var currentOperation: String?
    @Published var lastMessage: String?
    @Published var lastError: String?
    
    private let appIdKey = "feishu_app_id"
    private let appSecretKey = "feishu_app_secret"
    private let assetAppTokenKey = "feishu_asset_app_token"
    private let recordAppTokenKey = "feishu_record_app_token"
    private let legacyAppTokenKey = "feishu_app_token"
    private let assetTableIdKey = "feishu_asset_table_id"
    private let recordTableIdKey = "feishu_record_table_id"
    private let legacyTableIdKey = "feishu_table_id"
    private let accessTokenKey = "feishu_access_token"
    private let tokenExpiryKey = "feishu_token_expiry"
    private let preferencesSuiteName = "honghaoliu.AssetManager"
    private let defaultBaseAppToken = "Zj9zbNOBcaQpw0smtZDcu7R2n4d"
    private let defaultAssetTableId = "tblNjryuSQbfXpXM"
    private let defaultRecordTableId = "tbluOIuGYvgcU9b0"
    private let legacySingleBaseRecordTableId = "tbl4KiipDDV3F0YZ"
    
    private let baseURL = "https://open.feishu.cn/open-apis"
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()
    private let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()
    private lazy var defaults: UserDefaults = {
        UserDefaults(suiteName: preferencesSuiteName) ?? .standard
    }()
    
    init() {
        migrateLegacyConfigIfNeeded()
        loadConfig()
    }

    private func migrateLegacyConfigIfNeeded() {
        let standardDefaults = UserDefaults.standard
        let keys = [
            appIdKey,
            appSecretKey,
            assetAppTokenKey,
            recordAppTokenKey,
            legacyAppTokenKey,
            assetTableIdKey,
            recordTableIdKey,
            legacyTableIdKey,
            accessTokenKey
        ]

        for key in keys where defaults.object(forKey: key) == nil {
            if let value = standardDefaults.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }

        if defaults.object(forKey: tokenExpiryKey) == nil,
           let expiry = standardDefaults.object(forKey: tokenExpiryKey) {
            defaults.set(expiry, forKey: tokenExpiryKey)
        }
    }
    
    /// 加载配置
    private func loadConfig() {
        appId = defaults.string(forKey: appIdKey) ?? ""
        appSecret = defaults.string(forKey: appSecretKey) ?? ""
        let legacyAppToken = defaults.string(forKey: legacyAppTokenKey) ?? ""
        assetAppToken = defaults.string(forKey: assetAppTokenKey) ?? defaultBaseAppToken
        recordAppToken = defaults.string(forKey: recordAppTokenKey) ?? legacyAppToken
        if recordAppToken.isEmpty {
            recordAppToken = assetAppToken.isEmpty ? defaultBaseAppToken : assetAppToken
        }
        assetTableId = defaults.string(forKey: assetTableIdKey) ?? defaultAssetTableId
        let savedRecordTableId = defaults.string(forKey: recordTableIdKey)
        let legacyTableId = defaults.string(forKey: legacyTableIdKey)
        recordTableId = savedRecordTableId ?? legacyTableId ?? defaultRecordTableId
        if recordTableId == legacySingleBaseRecordTableId {
            recordTableId = defaultRecordTableId
            defaults.set(recordTableId, forKey: recordTableIdKey)
        }
        accessToken = defaults.string(forKey: accessTokenKey) ?? ""
        
        isConfigured = hasBaseConfig && canSyncRecords
        
        // 检查 token 是否过期
        if let expiry = defaults.object(forKey: tokenExpiryKey) as? Date {
            if expiry < Date() {
                accessToken = ""
            }
        }
    }
    
    /// 保存配置
    func saveConfig(
        appId: String,
        appSecret: String,
        assetAppToken: String,
        assetTableId: String,
        recordAppToken: String,
        recordTableId: String
    ) {
        self.appId = appId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.appSecret = appSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        self.assetAppToken = assetAppToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.assetTableId = assetTableId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.recordAppToken = recordAppToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.recordTableId = recordTableId.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.recordAppToken.isEmpty {
            self.recordAppToken = self.assetAppToken
        }
        if self.assetAppToken.isEmpty, !self.recordAppToken.isEmpty {
            self.assetAppToken = self.recordAppToken
        }
        if self.assetTableId.isEmpty {
            self.assetTableId = defaultAssetTableId
        }
        if self.recordTableId.isEmpty {
            self.recordTableId = defaultRecordTableId
        }
        
        defaults.set(self.appId, forKey: appIdKey)
        defaults.set(self.appSecret, forKey: appSecretKey)
        defaults.set(self.assetAppToken, forKey: assetAppTokenKey)
        defaults.set(self.assetTableId, forKey: assetTableIdKey)
        defaults.set(self.recordAppToken, forKey: recordAppTokenKey)
        defaults.set(self.recordTableId, forKey: recordTableIdKey)
        
        isConfigured = hasBaseConfig && canSyncRecords
        
        // 配置变更后重新获取 token
        if isConfigured {
            Task {
                await getAccessToken()
            }
        }
    }

    func isReadyForAutoSync() -> Bool {
        hasBaseConfig && canSyncAssets && canSyncRecords
    }
    
    /// 从 Wiki 链接提取 Table ID
    func extractTableId(from wikiURL: String) -> String? {
        guard let url = URL(string: wikiURL) else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        guard let queryItems = components?.queryItems else { return nil }
        return queryItems.first(where: { $0.name == "table" })?.value
    }

    /// 从多维表格链接提取 Base App Token
    func extractAppToken(from tableURL: String) -> String? {
        guard let url = URL(string: tableURL) else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard let baseIndex = components.firstIndex(of: "base"), components.indices.contains(baseIndex + 1) else {
            return nil
        }
        return components[baseIndex + 1]
    }

    /// 从多维表格链接提取 App Token 与 Table ID
    func extractTableConfig(from tableURL: String) -> (appToken: String, tableId: String)? {
        guard let appToken = extractAppToken(from: tableURL),
              let tableId = extractTableId(from: tableURL) else {
            return nil
        }
        return (appToken, tableId)
    }
    
    /// 从 Wiki 链接提取 View ID
    func extractViewId(from wikiURL: String) -> String? {
        guard let url = URL(string: wikiURL) else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        guard let queryItems = components?.queryItems else { return nil }
        return queryItems.first(where: { $0.name == "view" })?.value
    }
    
    /// 获取访问令牌
    func getAccessToken() async {
        currentOperation = "正在获取飞书访问令牌"
        guard let url = URL(string: "\(baseURL)/auth/v3/tenant_access_token/internal") else {
            lastError = "无效的 URL"
            currentOperation = nil
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "app_id": appId,
            "app_secret": appSecret
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   json["code"] as? Int == 0,
                   let token = json["tenant_access_token"] as? String,
                   let expire = json["expire"] as? Int {
                    
                    accessToken = token
                    defaults.set(token, forKey: accessTokenKey)
                    defaults.set(Date().addingTimeInterval(TimeInterval(expire)), forKey: tokenExpiryKey)
                    isConfigured = hasBaseConfig && canSyncRecords
                    lastMessage = "✅ 飞书连接成功"
                    currentOperation = nil
                    print("✅ 飞书 Token 获取成功")
                }
            } else {
                lastError = "飞书 Token 获取失败"
                currentOperation = nil
                print("❌ 飞书 Token 获取失败")
            }
        } catch {
            lastError = "飞书连接错误: \(error.localizedDescription)"
            currentOperation = nil
            print("❌ 飞书连接错误: \(error.localizedDescription)")
        }
    }
    
    func syncAsset(_ asset: macOS_Asset) async {
        beginOperation("正在同步资产：\(asset.assetName.isEmpty ? asset.id : asset.assetName)")
        guard canSyncAssets else { return }
        guard await prepareSyncing() else { return }
        defer { finishSyncing() }

        do {
            try await ensureRemoteSchemaIfNeeded()
            let fieldDefinitions = try await fetchFieldDefinitions(appToken: assetAppToken, tableId: assetTableId)
            let fieldTypeMap = Dictionary(uniqueKeysWithValues: fieldDefinitions.map { ($0.name, $0.type) })
            let availableFieldNames = Set(fieldTypeMap.keys)
            try validateAssetSchema(availableFieldNames)
            try await upsertRecord(
                appToken: assetAppToken,
                tableId: assetTableId,
                uniqueField: "外编号",
                uniqueValue: asset.id,
                fields: assetFields(
                    for: asset,
                    latestActiveRecord: nil,
                    fieldTypeMap: fieldTypeMap
                )
            )
            lastMessage = "✅ 已同步资产「\(asset.assetName)」"
        } catch {
            lastError = "资产同步失败: \(error.localizedDescription)"
        }
    }

    func syncOperationRecord(_ record: macOS_OperationRecord, asset: macOS_Asset) async {
        beginOperation("正在同步\(record.type.displayName)记录：\(record.assetName)")
        guard canSyncRecords else { return }
        guard await prepareSyncing() else { return }
        defer { finishSyncing() }

        do {
            try await ensureRemoteSchemaIfNeeded()
            let fieldDefinitions = try await fetchFieldDefinitions(appToken: recordAppToken, tableId: recordTableId)
            let fieldTypeMap = Dictionary(uniqueKeysWithValues: fieldDefinitions.map { ($0.name, $0.type) })
            let availableFieldNames = Set(fieldTypeMap.keys)
            let userDirectory = try await fetchOperatorDirectory(appToken: recordAppToken, tableId: recordTableId)
            let existingRecordId = try await findMatchingOperationRecordID(
                appToken: recordAppToken,
                tableId: recordTableId,
                record: record,
                availableFieldNames: availableFieldNames
            )
            try await upsertRecord(
                appToken: recordAppToken,
                tableId: recordTableId,
                fields: operationRecordFields(
                    for: record,
                    asset: asset,
                    userDirectory: userDirectory,
                    fieldTypeMap: fieldTypeMap
                ),
                existingRecordId: existingRecordId
            )
            lastMessage = "✅ 已同步\(record.type.displayName)记录"
        } catch {
            lastError = "记录同步失败: \(error.localizedDescription)"
        }
    }

    func syncAllData(assets: [macOS_Asset], records: [macOS_OperationRecord]) async {
        beginOperation("正在全量同步飞书：资产 \(assets.count) 个，记录 \(records.count) 条")
        guard hasBaseConfig else {
            lastError = "请先配置 App ID、App Secret 和 App Token"
            return
        }
        guard canSyncAssets else {
            lastError = "缺少资产表 ID，暂时无法同步资产列表"
            return
        }
        guard canSyncRecords else {
            lastError = "缺少记录表 ID，暂时无法同步出入库记录"
            return
        }
        guard await prepareSyncing() else { return }
        defer { finishSyncing() }

        do {
            try await ensureRemoteSchemaIfNeeded()
            let assetFieldDefinitions = try await fetchFieldDefinitions(appToken: assetAppToken, tableId: assetTableId)
            let assetFieldTypeMap = Dictionary(uniqueKeysWithValues: assetFieldDefinitions.map { ($0.name, $0.type) })
            let assetFieldNames = Set(assetFieldTypeMap.keys)
            try validateAssetSchema(assetFieldNames)

            let recordFieldDefinitions = try await fetchFieldDefinitions(appToken: recordAppToken, tableId: recordTableId)
            let recordFieldTypeMap = Dictionary(uniqueKeysWithValues: recordFieldDefinitions.map { ($0.name, $0.type) })
            let recordFieldNames = Set(recordFieldTypeMap.keys)

            let assetIndex = try await fetchRecordIndex(appToken: assetAppToken, tableId: assetTableId, uniqueField: "外编号")
            let assetRecordGroups = try await fetchRecordIDsGroupedByField(appToken: assetAppToken, tableId: assetTableId, uniqueField: "外编号")
            let userDirectory = try await fetchOperatorDirectory(appToken: recordAppToken, tableId: recordTableId)
            let existingRecordIDs = try await fetchExistingOperationRecordIDs(
                appToken: recordAppToken,
                tableId: recordTableId,
                availableFieldNames: recordFieldNames
            )
            let existingRecordIDGroups = try await fetchExistingOperationRecordIDGroups(
                appToken: recordAppToken,
                tableId: recordTableId,
                availableFieldNames: recordFieldNames
            )
            let latestActiveRecordByAssetID = latestActiveOperationRecordsByAsset(records)

            var assetSuccessCount = 0
            var recordSuccessCount = 0

            for asset in assets {
                try await upsertRecord(
                    appToken: assetAppToken,
                    tableId: assetTableId,
                    fields: assetFields(
                        for: asset,
                        latestActiveRecord: latestActiveRecordByAssetID[asset.id],
                        fieldTypeMap: assetFieldTypeMap
                    ),
                    existingRecordId: assetIndex[asset.id]
                )
                assetSuccessCount += 1
            }

            for record in records {
                let matchingAsset = assets.first(where: { $0.id == record.assetId })
                let fields = operationRecordFields(
                    for: record,
                    asset: matchingAsset,
                    userDirectory: userDirectory,
                    fieldTypeMap: recordFieldTypeMap
                )
                try await upsertRecord(
                    appToken: recordAppToken,
                    tableId: recordTableId,
                    fields: fields,
                    existingRecordId: existingRecordIDs[operationRecordFingerprint(for: record)]
                )
                recordSuccessCount += 1
            }

            let deletedAssetCount = try await deleteStaleAssetRecords(
                localAssets: assets,
                groupedRemoteRecordIDs: assetRecordGroups,
                retainedRecordIDs: assetIndex
            )
            let deletedRecordCount = try await deleteStaleOperationRecords(
                localRecords: records,
                groupedRemoteRecordIDs: existingRecordIDGroups,
                retainedRecordIDs: existingRecordIDs
            )

            lastMessage = "✅ 飞书全量同步完成：资产 \(assetSuccessCount) 条，记录 \(recordSuccessCount) 条，删除远端资产 \(deletedAssetCount) 条，删除远端记录 \(deletedRecordCount) 条"
        } catch {
            lastError = "飞书全量同步失败: \(error.localizedDescription)"
        }
    }

    func importRemoteData() async -> FeishuSyncSnapshot? {
        beginOperation("正在从飞书拉取最新数据")
        guard await prepareSyncing() else { return nil }
        defer { finishSyncing() }

        do {
            let snapshot = try await fetchRemoteSnapshot()
            let warningText = snapshot.warnings.isEmpty ? "" : "；\(snapshot.warnings.joined(separator: "；"))"
            lastMessage = "✅ 已从飞书读取 \(snapshot.assets.count) 个资产、\(snapshot.records.count) 条记录\(warningText)"
            return snapshot
        } catch {
            lastError = "从飞书导入失败: \(error.localizedDescription)"
            return nil
        }
    }

    func syncBidirectionally(localAssets: [macOS_Asset], localRecords: [macOS_OperationRecord]) async -> FeishuSyncSnapshot? {
        beginOperation("正在执行飞书双向同步")
        guard await prepareSyncing() else { return nil }
        defer { finishSyncing() }

        var warnings: [String] = []

        if canSyncAssets && canSyncRecords {
            do {
                try await syncAllDataOnce(assets: localAssets, records: localRecords)
            } catch {
                warnings.append("推送到飞书失败：\(error.localizedDescription)")
            }
        } else {
            if !canSyncAssets {
                warnings.append("资产表未配置完整")
            }
            if !canSyncRecords {
                warnings.append("记录表未配置完整")
            }
        }

        do {
            var snapshot = try await fetchRemoteSnapshot()
            snapshot.warnings.insert(contentsOf: warnings, at: 0)
            let warningText = snapshot.warnings.isEmpty ? "" : "；\(snapshot.warnings.joined(separator: "；"))"
            lastMessage = "✅ 飞书双向同步完成：读取资产 \(snapshot.assets.count) 个、记录 \(snapshot.records.count) 条\(warningText)"
            return snapshot
        } catch {
            let prefix = warnings.isEmpty ? "" : warnings.joined(separator: "；") + "；"
            lastError = "双向同步失败: \(prefix)\(error.localizedDescription)"
            return nil
        }
    }
    
    /// 格式化日期
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
    
    /// 测试连接
    func testConnection() async {
        beginOperation("正在测试飞书连接")
        await getAccessToken()
        if hasBaseConfig, !accessToken.isEmpty {
            do {
                let inspection = try await inspectRemoteTables()
                let chunks = [
                    inspection.assetSummary,
                    inspection.recordSummary
                ].filter { !$0.isEmpty }
                lastMessage = "✅ 飞书连接成功" + (chunks.isEmpty ? "" : "：" + chunks.joined(separator: "；"))
            } catch {
                lastError = "飞书连接成功，但读取表结构失败: \(error.localizedDescription)"
            }
        }
    }

    private var hasBaseConfig: Bool {
        !appId.isEmpty &&
        !appSecret.isEmpty &&
        (!recordAppToken.isEmpty || !assetAppToken.isEmpty)
    }

    private var canSyncAssets: Bool {
        !assetAppToken.isEmpty && !assetTableId.isEmpty
    }

    private var canSyncRecords: Bool {
        !recordAppToken.isEmpty && !recordTableId.isEmpty
    }

    private func prepareSyncing() async -> Bool {
        guard hasBaseConfig else {
            lastError = "请先配置 App ID、App Secret 和 App Token"
            return false
        }

        if accessToken.isEmpty {
            await getAccessToken()
        }

        guard !accessToken.isEmpty else {
            lastError = "飞书访问令牌获取失败"
            return false
        }

        isSyncing = true
        lastError = nil
        return true
    }

    private func finishSyncing() {
        isSyncing = false
        currentOperation = nil
    }

    private func beginOperation(_ text: String) {
        currentOperation = text
        lastMessage = text
        lastError = nil
    }

    private func assetFields(
        for asset: macOS_Asset,
        latestActiveRecord: macOS_OperationRecord?,
        fieldTypeMap: [String: Int]
    ) -> [String: Any] {
        let currentOperatorName: String
        switch asset.status {
        case .inStock:
            currentOperatorName = ""
        case .checkedOut, .maintenance, .scrapped:
            currentOperatorName = latestActiveRecord?.operatorName ?? ""
        }

        let secondaryStatus = latestActiveRecord?.estimatedReturnDate.map { shortDateFormatter.string(from: $0) }
            ?? structuredNoteValue(label: "二级状态", in: asset.note)

        let fields: [String: Any] = [
            "资产属性": "固定资产",
            "保管科室": structuredNoteValue(label: "保管科室", in: asset.note) ?? "",
            "资产专管": structuredNoteValue(label: "资产专管", in: asset.note) ?? "",
            "保管人": structuredNoteValue(label: "保管人", in: asset.note) ?? "",
            "使用人": currentOperatorName.isEmpty ? (structuredNoteValue(label: "使用人", in: asset.note) ?? "") : currentOperatorName,
            "一级状态": asset.status.displayName,
            "二级状态": secondaryStatus ?? "",
            "一级存放地": asset.location,
            "二级存放地": structuredNoteValue(label: "二级存放地", in: asset.note) ?? "",
            "其他附件": structuredNoteValue(label: "其他附件", in: asset.note) ?? "",
            "外编号": asset.id,
            "名称": asset.assetName,
            "型号": asset.modelName,
            "品牌": asset.brand,
            "内编号": asset.internalCode
        ]

        return filterFields(fields, availableFieldNames: Set(fieldTypeMap.keys))
    }

    private func operationRecordFields(
        for record: macOS_OperationRecord,
        asset: macOS_Asset?,
        userDirectory: [String: String],
        fieldTypeMap: [String: Int]
    ) -> [String: Any] {
        var note = record.note ?? ""
        var fields: [String: Any] = [
            "资产名称": record.assetName,
            "外编号": record.assetId,
            "型号": asset?.modelName ?? "",
            "品牌": asset?.brand ?? "",
            "操作类型": record.type.displayName,
            "操作时间": valueForDateField(record.timestamp, fieldName: "操作时间", fieldTypeMap: fieldTypeMap)
        ]

        if let estimatedReturnDate = record.estimatedReturnDate {
            fields["预计归还"] = valueForDateField(estimatedReturnDate, fieldName: "预计归还", fieldTypeMap: fieldTypeMap)
        }

        if fieldTypeMap["记录ID"] != nil {
            fields["记录ID"] = record.id.uuidString
        }

        if let operatorFieldType = fieldTypeMap["操作人"] {
            if operatorFieldType == 11 {
                if let operatorId = resolveOperatorIdentifier(record.operatorName, userDirectory: userDirectory) {
                    fields["操作人"] = [["id": operatorId]]
                } else if !record.operatorName.isEmpty {
                    note = note.isEmpty ? "操作人：\(record.operatorName)" : "操作人：\(record.operatorName)\n\(note)"
                }
            } else if !record.operatorName.isEmpty {
                fields["操作人"] = record.operatorName
            }
        } else if !record.operatorName.isEmpty {
            note = note.isEmpty ? "操作人：\(record.operatorName)" : "操作人：\(record.operatorName)\n\(note)"
        }

        if fieldTypeMap["多行文本"] != nil {
            fields["多行文本"] = "\(record.type.displayName) - \(record.assetName) - \(formattedDate(record.timestamp))"
        }

        fields["备注"] = note
        return filterFields(fields, availableFieldNames: Set(fieldTypeMap.keys))
    }

    private func syncAllDataOnce(assets: [macOS_Asset], records: [macOS_OperationRecord]) async throws {
        try await ensureRemoteSchemaIfNeeded()
        let assetFieldDefinitions = try await fetchFieldDefinitions(appToken: assetAppToken, tableId: assetTableId)
        let assetFieldTypeMap = Dictionary(uniqueKeysWithValues: assetFieldDefinitions.map { ($0.name, $0.type) })
        let assetFieldNames = Set(assetFieldTypeMap.keys)
        try validateAssetSchema(assetFieldNames)

        let recordFieldDefinitions = try await fetchFieldDefinitions(appToken: recordAppToken, tableId: recordTableId)
        let recordFieldTypeMap = Dictionary(uniqueKeysWithValues: recordFieldDefinitions.map { ($0.name, $0.type) })
        let recordFieldNames = Set(recordFieldTypeMap.keys)

        let assetIndex = try await fetchRecordIndex(appToken: assetAppToken, tableId: assetTableId, uniqueField: "外编号")
        let assetRecordGroups = try await fetchRecordIDsGroupedByField(appToken: assetAppToken, tableId: assetTableId, uniqueField: "外编号")
        let userDirectory = try await fetchOperatorDirectory(appToken: recordAppToken, tableId: recordTableId)
        let existingRecordIDs = try await fetchExistingOperationRecordIDs(
            appToken: recordAppToken,
            tableId: recordTableId,
            availableFieldNames: recordFieldNames
        )
        let existingRecordIDGroups = try await fetchExistingOperationRecordIDGroups(
            appToken: recordAppToken,
            tableId: recordTableId,
            availableFieldNames: recordFieldNames
        )
        let latestActiveRecordByAssetID = latestActiveOperationRecordsByAsset(records)

        for asset in assets {
            try await upsertRecord(
                appToken: assetAppToken,
                tableId: assetTableId,
                fields: assetFields(
                    for: asset,
                    latestActiveRecord: latestActiveRecordByAssetID[asset.id],
                    fieldTypeMap: assetFieldTypeMap
                ),
                existingRecordId: assetIndex[asset.id]
            )
        }

        for record in records {
            let matchingAsset = assets.first(where: { $0.id == record.assetId })
            try await upsertRecord(
                appToken: recordAppToken,
                tableId: recordTableId,
                fields: operationRecordFields(
                    for: record,
                    asset: matchingAsset,
                    userDirectory: userDirectory,
                    fieldTypeMap: recordFieldTypeMap
                ),
                existingRecordId: existingRecordIDs[operationRecordFingerprint(for: record)]
            )
        }

        _ = try await deleteStaleAssetRecords(
            localAssets: assets,
            groupedRemoteRecordIDs: assetRecordGroups,
            retainedRecordIDs: assetIndex
        )
        _ = try await deleteStaleOperationRecords(
            localRecords: records,
            groupedRemoteRecordIDs: existingRecordIDGroups,
            retainedRecordIDs: existingRecordIDs
        )
    }

    private func fetchRemoteSnapshot() async throws -> FeishuSyncSnapshot {
        var assets: [macOS_Asset] = []
        var records: [macOS_OperationRecord] = []
        var warnings: [String] = []

        if canSyncAssets {
            let fieldDefinitions = try await fetchFieldDefinitions(appToken: assetAppToken, tableId: assetTableId)
            let fieldNames = Set(fieldDefinitions.map(\.name))
            let missingAssetFields = missingAssetFields(from: fieldNames)

            if missingAssetFields.isEmpty {
                let remoteAssets = try await fetchAllRecords(appToken: assetAppToken, tableId: assetTableId)
                assets = remoteAssets.compactMap { remoteAsset(from: $0.fields) }
            } else {
                warnings.append("资产表缺少字段：\(missingAssetFields.joined(separator: "、"))")
            }
        }

        if canSyncRecords {
            let remoteRecords = try await fetchAllRecords(appToken: recordAppToken, tableId: recordTableId)
            records = remoteRecords.compactMap { remoteOperationRecord(recordId: $0.recordId, fields: $0.fields) }
        }

        return FeishuSyncSnapshot(assets: assets, records: records, warnings: warnings)
    }

    private func inspectRemoteTables() async throws -> FeishuSyncInspection {
        var assetSummary = ""
        var recordSummary = ""

        if canSyncAssets {
            let fields = try await fetchFieldDefinitions(appToken: assetAppToken, tableId: assetTableId)
            let fieldNames = Set(fields.map(\.name))
            let missing = missingAssetFields(from: fieldNames)
            if missing.isEmpty {
                assetSummary = "资产表字段完整"
            } else {
                assetSummary = "资产表缺少：\(missing.joined(separator: "、"))"
            }
        }

        if canSyncRecords {
            let fields = try await fetchFieldDefinitions(appToken: recordAppToken, tableId: recordTableId)
            let fieldNames = Set(fields.map(\.name))
            let missing = missingRecordFields(from: fieldNames)
            let recordIdentity = fieldNames.contains("记录ID") ? "使用记录ID对齐" : "将按外编号+操作类型+操作时间对齐"
            if missing.isEmpty {
                recordSummary = "记录表可读，\(recordIdentity)"
            } else {
                recordSummary = "记录表缺少：\(missing.joined(separator: "、"))，\(recordIdentity)"
            }
        }

        return FeishuSyncInspection(assetSummary: assetSummary, recordSummary: recordSummary)
    }

    private func validateAssetSchema(_ availableFieldNames: Set<String>) throws {
        let missing = missingAssetFields(from: availableFieldNames)
        guard missing.isEmpty else {
            throw FeishuBitableError.apiError("资产表缺少字段：\(missing.joined(separator: "、"))")
        }
    }

    private func missingAssetFields(from availableFieldNames: Set<String>) -> [String] {
        assetRequiredFields.filter { !availableFieldNames.contains($0) }
    }

    private func missingRecordFields(from availableFieldNames: Set<String>) -> [String] {
        recordRequiredFields.filter { !availableFieldNames.contains($0) }
    }

    private var assetRequiredFields: [String] {
        [
            "资产属性", "名称", "型号", "品牌", "外编号", "内编号",
            "保管科室", "资产专管", "保管人", "使用人",
            "一级状态", "二级状态", "一级存放地", "二级存放地", "其他附件"
        ]
    }

    private var recordRequiredFields: [String] {
        ["记录ID", "资产名称", "外编号", "型号", "品牌", "操作类型", "操作人", "操作时间", "备注", "预计归还"]
    }

    private var assetFieldSpecs: [FeishuFieldSpec] {
        [
            FeishuFieldSpec(name: "资产属性", type: 1),
            FeishuFieldSpec(name: "名称", type: 1),
            FeishuFieldSpec(name: "外编号", type: 1),
            FeishuFieldSpec(name: "型号", type: 1),
            FeishuFieldSpec(name: "品牌", type: 1),
            FeishuFieldSpec(name: "内编号", type: 1),
            FeishuFieldSpec(name: "保管科室", type: 1),
            FeishuFieldSpec(name: "资产专管", type: 1),
            FeishuFieldSpec(name: "保管人", type: 1),
            FeishuFieldSpec(name: "使用人", type: 1),
            FeishuFieldSpec(name: "一级状态", type: 1),
            FeishuFieldSpec(name: "二级状态", type: 1),
            FeishuFieldSpec(name: "一级存放地", type: 1),
            FeishuFieldSpec(name: "二级存放地", type: 1),
            FeishuFieldSpec(name: "其他附件", type: 1)
        ]
    }

    private var recordFieldSpecs: [FeishuFieldSpec] {
        [
            FeishuFieldSpec(name: "记录ID", type: 1),
            FeishuFieldSpec(name: "资产名称", type: 1),
            FeishuFieldSpec(name: "外编号", type: 1),
            FeishuFieldSpec(name: "型号", type: 1),
            FeishuFieldSpec(name: "品牌", type: 1),
            FeishuFieldSpec(name: "操作类型", type: 1),
            FeishuFieldSpec(name: "操作人", type: 1),
            FeishuFieldSpec(name: "操作时间", type: 5, property: ["date_formatter": "yyyy/MM/dd HH:mm", "auto_fill": false]),
            FeishuFieldSpec(name: "备注", type: 1),
            FeishuFieldSpec(name: "预计归还", type: 5, property: ["date_formatter": "yyyy/MM/dd HH:mm", "auto_fill": false])
        ]
    }

    private func filterFields(_ fields: [String: Any], availableFieldNames: Set<String>) -> [String: Any] {
        fields.reduce(into: [:]) { partialResult, item in
            if availableFieldNames.contains(item.key) {
                partialResult[item.key] = item.value
            }
        }
    }

    private func ensureRemoteSchemaIfNeeded() async throws {
        if canSyncAssets {
            try await ensureTableFields(
                appToken: assetAppToken,
                tableId: assetTableId,
                fieldSpecs: assetFieldSpecs,
                label: "资产表"
            )
        }
        if canSyncRecords {
            try await ensureTableFields(
                appToken: recordAppToken,
                tableId: recordTableId,
                fieldSpecs: recordFieldSpecs,
                label: "记录表"
            )
        }
    }

    private func ensureTableFields(
        appToken: String,
        tableId: String,
        fieldSpecs: [FeishuFieldSpec],
        label: String
    ) async throws {
        let existingFields = try await fetchFieldDefinitions(appToken: appToken, tableId: tableId)
        let existingFieldNames = Set(existingFields.map(\.name))
        let missingSpecs = fieldSpecs.filter { !existingFieldNames.contains($0.name) }
        guard !missingSpecs.isEmpty else { return }

        currentOperation = "正在补齐\(label)字段"
        for spec in missingSpecs {
            try await createField(appToken: appToken, tableId: tableId, spec: spec)
        }
        lastMessage = "已自动补齐\(label)字段：\(missingSpecs.map(\.name).joined(separator: "、"))"
    }

    private func valueForDateField(_ date: Date, fieldName: String, fieldTypeMap: [String: Int]) -> Any {
        if fieldTypeMap[fieldName] == 5 {
            return timestampValue(date)
        }
        return formattedDate(date)
    }

    private func latestActiveOperationRecordsByAsset(_ records: [macOS_OperationRecord]) -> [String: macOS_OperationRecord] {
        var result: [String: macOS_OperationRecord] = [:]

        for record in records.sorted(by: { $0.timestamp > $1.timestamp }) {
            switch record.type {
            case .checkOut, .repair, .scrap:
                if result[record.assetId] == nil {
                    result[record.assetId] = record
                }
            case .checkIn:
                continue
            }
        }

        return result
    }

    private func fetchExistingOperationRecordIDs(
        appToken: String,
        tableId: String,
        availableFieldNames: Set<String>
    ) async throws -> [String: String] {
        let records = try await fetchAllRecords(appToken: appToken, tableId: tableId)
        var result: [String: String] = [:]

        for record in records {
            for key in operationRecordLookupKeys(fields: record.fields, availableFieldNames: availableFieldNames) {
                if !key.isEmpty {
                    result[key] = record.recordId
                }
            }
        }

        return result
    }

    private func fetchExistingOperationRecordIDGroups(
        appToken: String,
        tableId: String,
        availableFieldNames: Set<String>
    ) async throws -> [String: [String]] {
        let records = try await fetchAllRecords(appToken: appToken, tableId: tableId)
        var result: [String: [String]] = [:]

        for record in records {
            for key in operationRecordLookupKeys(fields: record.fields, availableFieldNames: availableFieldNames) where !key.isEmpty {
                result[key, default: []].append(record.recordId)
            }
        }

        return result
    }

    private func findMatchingOperationRecordID(
        appToken: String,
        tableId: String,
        record: macOS_OperationRecord,
        availableFieldNames: Set<String>
    ) async throws -> String? {
        let records = try await fetchAllRecords(appToken: appToken, tableId: tableId)
        let targetKeys = Set(operationRecordLookupKeys(for: record))

        for remoteRecord in records {
            let remoteKeys = Set(operationRecordLookupKeys(fields: remoteRecord.fields, availableFieldNames: availableFieldNames))
            if !targetKeys.isDisjoint(with: remoteKeys) {
                return remoteRecord.recordId
            }
        }

        return nil
    }

    private func deleteStaleAssetRecords(
        localAssets: [macOS_Asset],
        groupedRemoteRecordIDs: [String: [String]],
        retainedRecordIDs: [String: String]
    ) async throws -> Int {
        let localAssetIDs = Set(localAssets.map(\.id))
        var staleRecordIDs: [String] = []

        for (assetID, recordIDs) in groupedRemoteRecordIDs {
            if !localAssetIDs.contains(assetID) {
                staleRecordIDs.append(contentsOf: recordIDs)
                continue
            }

            if recordIDs.count > 1, let retainedID = retainedRecordIDs[assetID] {
                staleRecordIDs.append(contentsOf: recordIDs.filter { $0 != retainedID })
            }
        }

        return try await deleteRecords(appToken: assetAppToken, tableId: assetTableId, recordIDs: staleRecordIDs)
    }

    private func deleteStaleOperationRecords(
        localRecords: [macOS_OperationRecord],
        groupedRemoteRecordIDs: [String: [String]],
        retainedRecordIDs: [String: String]
    ) async throws -> Int {
        let localFingerprints = Set(localRecords.map(operationRecordFingerprint(for:)))
        var staleRecordIDs: [String] = []

        for (fingerprint, recordIDs) in groupedRemoteRecordIDs {
            if !localFingerprints.contains(fingerprint) {
                staleRecordIDs.append(contentsOf: recordIDs)
                continue
            }

            if recordIDs.count > 1, let retainedID = retainedRecordIDs[fingerprint] {
                staleRecordIDs.append(contentsOf: recordIDs.filter { $0 != retainedID })
            }
        }

        return try await deleteRecords(appToken: recordAppToken, tableId: recordTableId, recordIDs: staleRecordIDs)
    }

    private func operationRecordFingerprint(for record: macOS_OperationRecord) -> String {
        [
            record.assetId,
            record.type.rawValue,
            String(timestampValue(record.timestamp))
        ].joined(separator: "|")
    }

    private func operationRecordLookupKeys(for record: macOS_OperationRecord) -> [String] {
        [
            record.id.uuidString,
            operationRecordFingerprint(for: record)
        ]
    }

    private func operationRecordFingerprint(fields: [String: Any], availableFieldNames: Set<String>) -> String {
        if availableFieldNames.contains("记录ID"), let value = stringValue(for: fields["记录ID"]), !value.isEmpty {
            return value
        }

        let assetId = stringValue(for: fields["外编号"]) ?? ""
        let type = stringValue(for: fields["操作类型"]) ?? ""
        let timestamp = normalizedTimestampString(from: fields["操作时间"]) ?? ""
        return [assetId, type, timestamp].joined(separator: "|")
    }

    private func operationRecordLookupKeys(fields: [String: Any], availableFieldNames: Set<String>) -> [String] {
        var keys: [String] = []

        if availableFieldNames.contains("记录ID"),
           let value = stringValue(for: fields["记录ID"]),
           !value.isEmpty {
            keys.append(value)
        }

        let fallback = operationRecordFallbackFingerprint(fields: fields)
        if !fallback.isEmpty {
            keys.append(fallback)
        }

        return keys
    }

    private func operationRecordFallbackFingerprint(fields: [String: Any]) -> String {
        let assetId = stringValue(for: fields["外编号"]) ?? ""
        let type = stringValue(for: fields["操作类型"]) ?? ""
        let timestamp = normalizedTimestampString(from: fields["操作时间"]) ?? ""
        return [assetId, type, timestamp].joined(separator: "|")
    }

    private func remoteAsset(from fields: [String: Any]) -> macOS_Asset? {
        let assetId = stringValue(for: fields["外编号"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !assetId.isEmpty else { return nil }

        let assetName = stringValue(for: fields["名称"]) ?? ""
        let statusText = stringValue(for: fields["一级状态"]) ?? macOS_AssetStatus.inStock.rawValue
        let status = macOS_AssetStatus.fromStoredValue(statusText)

        return macOS_Asset(
            id: assetId,
            assetName: assetName,
            modelName: stringValue(for: fields["型号"]) ?? "",
            brand: stringValue(for: fields["品牌"]) ?? "",
            status: status,
            internalCode: stringValue(for: fields["内编号"]) ?? "",
            location: stringValue(for: fields["一级存放地"]) ?? "",
            purchaseDate: nil,
            note: rebuildAssetNote(from: fields),
            lastUpdated: Date()
        )
    }

    private func remoteOperationRecord(recordId: String, fields: [String: Any]) -> macOS_OperationRecord? {
        let assetId = stringValue(for: fields["外编号"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !assetId.isEmpty else { return nil }

        let typeText = stringValue(for: fields["操作类型"]) ?? ""
        guard let type = macOS_OperationType(rawValue: typeText) else { return nil }

        let recordUUID: UUID
        if let explicitID = stringValue(for: fields["记录ID"]), let parsed = UUID(uuidString: explicitID) {
            recordUUID = parsed
        } else {
            recordUUID = deterministicUUID(seed: recordId)
        }

        return macOS_OperationRecord(
            id: recordUUID,
            assetId: assetId,
            assetName: stringValue(for: fields["资产名称"]) ?? "",
            type: type,
            operatorName: operatorName(from: fields["操作人"]) ?? extractOperatorName(from: stringValue(for: fields["备注"])),
            timestamp: dateValue(for: fields["操作时间"]) ?? Date(),
            note: stringValue(for: fields["备注"]),
            estimatedReturnDate: dateValue(for: fields["预计归还"])
        )
    }

    private func operatorName(from value: Any?) -> String? {
        guard let users = value as? [[String: Any]], let user = users.first else { return nil }
        return (user["name"] as? String) ?? (user["en_name"] as? String)
    }

    private func extractOperatorName(from note: String?) -> String {
        guard let note, note.hasPrefix("操作人：") else { return "当前用户" }
        let raw = note.components(separatedBy: "\n").first ?? note
        return raw.replacingOccurrences(of: "操作人：", with: "")
    }

    private func dateValue(for value: Any?) -> Date? {
        switch value {
        case let number as NSNumber:
            return Date(timeIntervalSince1970: number.doubleValue / 1000)
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return nil
            }
            if let milliseconds = Double(trimmed) {
                return Date(timeIntervalSince1970: milliseconds / 1000)
            }
            return dateFormatter.date(from: trimmed) ?? shortDateFormatter.date(from: trimmed)
        default:
            return nil
        }
    }

    private func normalizedTimestampString(from value: Any?) -> String? {
        if let date = dateValue(for: value) {
            return String(timestampValue(date))
        }
        return nil
    }

    private func deterministicUUID(seed: String) -> UUID {
        let digest = SHA256.hash(data: Data(seed.utf8))
        let bytes = Array(digest.prefix(16))
        let uuidBytes: [UInt8] = [
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ]

        return UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
    }

    private func fetchRecordIndex(appToken: String, tableId: String, uniqueField: String) async throws -> [String: String] {
        let records = try await fetchAllRecords(appToken: appToken, tableId: tableId)
        var index: [String: String] = [:]

        for record in records {
            if let value = stringValue(for: record.fields[uniqueField]), !value.isEmpty {
                index[value] = record.recordId
            }
        }

        return index
    }

    private func fetchRecordIDsGroupedByField(appToken: String, tableId: String, uniqueField: String) async throws -> [String: [String]] {
        let records = try await fetchAllRecords(appToken: appToken, tableId: tableId)
        var groups: [String: [String]] = [:]

        for record in records {
            if let value = stringValue(for: record.fields[uniqueField]), !value.isEmpty {
                groups[value, default: []].append(record.recordId)
            }
        }

        return groups
    }

    private func fetchOperatorDirectory(appToken: String, tableId: String) async throws -> [String: String] {
        let records = try await fetchAllRecords(appToken: appToken, tableId: tableId)
        var directory: [String: String] = [:]

        for record in records {
            guard let users = record.fields["操作人"] as? [[String: Any]] else { continue }
            for user in users {
                if let name = user["name"] as? String, let id = user["id"] as? String, !name.isEmpty {
                    directory[name] = id
                }
            }
        }

        return directory
    }

    private func upsertRecord(appToken: String, tableId: String, uniqueField: String, uniqueValue: String, fields: [String: Any]) async throws {
        let index = try await fetchRecordIndex(appToken: appToken, tableId: tableId, uniqueField: uniqueField)
        try await upsertRecord(appToken: appToken, tableId: tableId, fields: fields, existingRecordId: index[uniqueValue])
    }

    private func upsertRecord(appToken: String, tableId: String, fields: [String: Any], existingRecordId: String?) async throws {
        if let existingRecordId {
            do {
                _ = try await requestRecord(
                    appToken: appToken,
                    tableId: tableId,
                    method: "PUT",
                    recordId: existingRecordId,
                    body: ["fields": fields]
                )
                return
            } catch let FeishuBitableError.apiError(message) where shouldRetryAsCreate(for: message) {
                // Some legacy or manually edited rows can leave us with a stale record reference.
                // In that case, create a fresh row instead of aborting the whole sync.
                _ = try await requestRecord(
                    appToken: appToken,
                    tableId: tableId,
                    method: "POST",
                    body: ["fields": fields]
                )
                return
            } catch {
                throw error
            }
        }

        _ = try await requestRecord(
            appToken: appToken,
            tableId: tableId,
            method: "POST",
            body: ["fields": fields]
        )
    }

    private func deleteRecords(appToken: String, tableId: String, recordIDs: [String]) async throws -> Int {
        let uniqueRecordIDs = Array(Set(recordIDs))
        guard !uniqueRecordIDs.isEmpty else { return 0 }

        for recordID in uniqueRecordIDs {
            _ = try await requestRecord(
                appToken: appToken,
                tableId: tableId,
                method: "DELETE",
                recordId: recordID
            )
        }

        return uniqueRecordIDs.count
    }

    private func fetchAllRecords(appToken: String, tableId: String) async throws -> [(recordId: String, fields: [String: Any])] {
        var result: [(recordId: String, fields: [String: Any])] = []
        var pageToken: String?

        repeat {
            var components = URLComponents(string: "\(baseURL)/bitable/v1/apps/\(appToken)/tables/\(tableId)/records")
            components?.queryItems = [
                URLQueryItem(name: "page_size", value: "500")
            ]
            if let pageToken {
                components?.queryItems?.append(URLQueryItem(name: "page_token", value: pageToken))
            }

            guard let url = components?.url else {
                throw FeishuBitableError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            let json = try parseResponseJSON(data, response: response)
            let dataObject = json["data"] as? [String: Any]
            let items = dataObject?["items"] as? [[String: Any]] ?? []
            pageToken = dataObject?["page_token"] as? String
            let hasMore = dataObject?["has_more"] as? Bool ?? false

            for item in items {
                guard let recordId = item["record_id"] as? String else { continue }
                let fields = item["fields"] as? [String: Any] ?? [:]
                result.append((recordId: recordId, fields: fields))
            }

            if !hasMore {
                pageToken = nil
            }
        } while pageToken != nil

        return result
    }

    private func fetchFieldDefinitions(appToken: String, tableId: String) async throws -> [FeishuFieldDefinition] {
        guard let url = URL(string: "\(baseURL)/bitable/v1/apps/\(appToken)/tables/\(tableId)/fields?page_size=500") else {
            throw FeishuBitableError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = try parseResponseJSON(data, response: response)
        let items = (json["data"] as? [String: Any])?["items"] as? [[String: Any]] ?? []

        return items.compactMap { item in
            guard let name = item["field_name"] as? String,
                  let type = item["type"] as? Int else { return nil }
            return FeishuFieldDefinition(name: name, type: type)
        }
    }

    @discardableResult
    private func createField(appToken: String, tableId: String, spec: FeishuFieldSpec) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/bitable/v1/apps/\(appToken)/tables/\(tableId)/fields") else {
            throw FeishuBitableError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "field_name": spec.name,
            "type": spec.type
        ]
        if let property = spec.property {
            body["property"] = property
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        return try parseResponseJSON(data, response: response)
    }

    @discardableResult
    private func requestRecord(appToken: String, tableId: String, method: String, recordId: String? = nil, body: [String: Any]? = nil) async throws -> [String: Any] {
        var path = "\(baseURL)/bitable/v1/apps/\(appToken)/tables/\(tableId)/records"
        if let recordId {
            path += "/\(recordId)"
        }

        guard let url = URL(string: path) else {
            throw FeishuBitableError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        return try parseResponseJSON(data, response: response)
    }

    private func parseResponseJSON(_ data: Data, response: URLResponse? = nil) throws -> [String: Any] {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let code = json["code"] as? Int ?? -1
        if code != 0 {
            let message = json["msg"] as? String ?? "未知错误"
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let details = (json["error"] as? [String: Any])?["message"] as? String
            throw FeishuBitableError.apiError(
                [message, details, statusCode.map { "HTTP \($0)" }]
                    .compactMap { $0 }
                    .joined(separator: " | ")
            )
        }
        return json
    }

    private func shouldRetryAsCreate(for message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("deleted")
            || normalized.contains("has been deleted")
            || normalized.contains("record is not found")
            || normalized.contains("record not found")
            || normalized.contains("not found")
    }

    private func stringValue(for value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let array as [String]:
            return array.joined(separator: ",")
        case let array as [[String: Any]]:
            return array.compactMap { $0["text"] as? String ?? $0["name"] as? String }.joined(separator: ",")
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private func structuredNoteValue(label: String, in note: String?) -> String? {
        guard let note else { return nil }
        let prefix = "\(label)："
        for line in note.components(separatedBy: .newlines) {
            guard line.hasPrefix(prefix) else { continue }
            let value = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func rebuildAssetNote(from fields: [String: Any]) -> String? {
        let labels = ["保管科室", "资产专管", "保管人", "使用人", "二级状态", "二级存放地", "其他附件"]
        let lines = labels.compactMap { label -> String? in
            guard let value = stringValue(for: fields[label])?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return "\(label)：\(value)"
        }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    private func timestampValue(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }

    private func resolveOperatorIdentifier(_ operatorName: String, userDirectory: [String: String]) -> String? {
        if operatorName.hasPrefix("ou_") {
            return operatorName
        }
        return userDirectory[operatorName]
    }
}

enum FeishuBitableError: LocalizedError {
    case invalidURL
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的飞书 API 地址"
        case .apiError(let message):
            return message
        }
    }
}

struct FeishuFieldDefinition {
    let name: String
    let type: Int
}

struct FeishuFieldSpec {
    let name: String
    let type: Int
    let property: [String: Any]?

    init(name: String, type: Int, property: [String: Any]? = nil) {
        self.name = name
        self.type = type
        self.property = property
    }
}

struct FeishuSyncSnapshot {
    var assets: [macOS_Asset]
    var records: [macOS_OperationRecord]
    var warnings: [String]
}

struct FeishuSyncInspection {
    let assetSummary: String
    let recordSummary: String
}
