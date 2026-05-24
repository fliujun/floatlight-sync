# 浮光 Reminders Sync - Native Messaging Protocol

## 概述

Chrome 扩展通过 Native Messaging 与本地 Swift Helper 通信。
协议基于 JSON，每条消息前有 4 字节小端序长度头（Chrome Native Messaging 标准）。

## 消息格式

### 请求（扩展 → Helper）

```json
{
  "id": "msg_001",
  "action": "actionName",
  "payload": { ... }
}
```

### 响应（Helper → 扩展）

```json
{
  "id": "msg_001",
  "success": true,
  "data": { ... }
}
```

### 推送事件（Helper → 扩展，实时变更通知）

```json
{
  "id": null,
  "event": "reminders_changed",
  "data": { ... }
}
```

---

## Actions

### 1. `ping` - 检测 Helper 是否存活

**请求：**
```json
{ "id": "1", "action": "ping", "payload": {} }
```

**响应：**
```json
{ "id": "1", "success": true, "data": { "version": "1.0.0", "os": "macOS 14.5" } }
```

---

### 2. `get_lists` - 获取提醒事项列表

**请求：**
```json
{ "id": "2", "action": "get_lists", "payload": {} }
```

**响应：**
```json
{
  "id": "2", "success": true,
  "data": {
    "lists": [
      { "id": "ekListId", "title": "浮光", "sections": [
        { "id": "ekSectionId", "title": "工作" },
        { "id": "ekSectionId2", "title": "生活" }
      ]}
    ]
  }
}
```

---

### 3. `ensure_list` - 确保"浮光"列表存在（不存在则创建）

**请求：**
```json
{ "id": "3", "action": "ensure_list", "payload": { "title": "浮光" } }
```

**响应：**
```json
{ "id": "3", "success": true, "data": { "listId": "ekListId", "created": false } }
```

---

### 4. `ensure_section` - 确保指定 section 存在

**请求：**
```json
{ "id": "4", "action": "ensure_section", "payload": { "listId": "ekListId", "title": "工作" } }
```

**响应：**
```json
{ "id": "4", "success": true, "data": { "sectionId": "ekSectionId", "created": true } }
```

---

### 5. `get_reminders` - 获取"浮光"列表所有提醒

**请求：**
```json
{ "id": "5", "action": "get_reminders", "payload": { "listId": "ekListId", "includeCompleted": true } }
```

**响应：**
```json
{
  "id": "5", "success": true,
  "data": {
    "reminders": [
      {
        "ekId": "reminder_identifier",
        "title": "写周报",
        "isCompleted": false,
        "flagged": true,
        "notes": "记得抄送老板",
        "dueDate": "2025-01-20T09:00:00Z",
        "sectionId": "ekSectionId",
        "creationDate": "2025-01-15T10:30:00Z",
        "modificationDate": "2025-01-16T08:00:00Z"
      }
    ]
  }
}
```

---

### 6. `create_reminder` - 创建提醒

**请求：**
```json
{
  "id": "6", "action": "create_reminder",
  "payload": {
    "listId": "ekListId",
    "sectionId": "ekSectionId",
    "title": "新任务",
    "notes": "",
    "dueDate": null,
    "flagged": false
  }
}
```

**响应：**
```json
{ "id": "6", "success": true, "data": { "ekId": "new_reminder_id", "creationDate": "...", "modificationDate": "..." } }
```

---

### 7. `update_reminder` - 更新提醒

**请求：**
```json
{
  "id": "7", "action": "update_reminder",
  "payload": {
    "ekId": "reminder_identifier",
    "title": "改后标题",
    "isCompleted": true,
    "flagged": false,
    "notes": "备注内容",
    "dueDate": "2025-01-22T18:00:00Z",
    "sectionId": "newSectionId"
  }
}
```

**响应：**
```json
{ "id": "7", "success": true, "data": { "modificationDate": "..." } }
```

---

### 8. `delete_reminder` - 删除提醒

**请求：**
```json
{ "id": "8", "action": "delete_reminder", "payload": { "ekId": "reminder_identifier" } }
```

**响应：**
```json
{ "id": "8", "success": true, "data": {} }
```

---

### 9. `batch_sync` - 批量同步（首次合并用）

**请求：**
```json
{
  "id": "9", "action": "batch_sync",
  "payload": {
    "listId": "ekListId",
    "reminders": [
      {
        "pluginId": "abc123",
        "title": "写周报",
        "isCompleted": false,
        "flagged": true,
        "notes": "",
        "dueDate": null,
        "sectionTitle": "工作",
        "createdAt": 1705312200000,
        "modifiedAt": 1705398600000
      }
    ]
  }
}
```

**响应：** 返回映射关系
```json
{
  "id": "9", "success": true,
  "data": {
    "mappings": [
      { "pluginId": "abc123", "ekId": "ek_reminder_001", "action": "matched" },
      { "pluginId": "def456", "ekId": "ek_reminder_002", "action": "pushed" },
      { "pluginId": null, "ekId": "ek_reminder_003", "action": "pulled", "reminder": { ... } }
    ]
  }
}
```

`action` 值：
- `matched`: 两边匹配上了，已按最新修改时间同步
- `pushed`: 插件→苹果（新建）
- `pulled`: 苹果→插件（新条目需要拉取）

---

## 推送事件

### `reminders_changed` - 提醒事项有变更

Helper 监听 `EKEventStoreChangedNotification`，有变化时推送：

```json
{
  "id": null,
  "event": "reminders_changed",
  "data": {
    "listId": "ekListId",
    "changes": [
      { "ekId": "xxx", "type": "modified", "reminder": { ... } },
      { "ekId": "yyy", "type": "deleted" },
      { "ekId": "zzz", "type": "added", "reminder": { ... } }
    ]
  }
}
```

---

## 错误响应

```json
{
  "id": "msg_001",
  "success": false,
  "error": {
    "code": "ACCESS_DENIED",
    "message": "用户未授权访问提醒事项"
  }
}
```

错误码：
- `ACCESS_DENIED`: 未获得提醒事项访问权限
- `LIST_NOT_FOUND`: 指定列表不存在
- `REMINDER_NOT_FOUND`: 指定提醒不存在
- `SECTION_NOT_SUPPORTED`: 系统版本不支持 Section（macOS < 14）
- `INTERNAL_ERROR`: 内部错误

---

## Native Messaging Host 配置

文件路径：`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/me.vkr.fl.sync.json`

```json
{
  "name": "me.vkr.fl.sync",
  "description": "浮光提醒事项同步 Helper",
  "path": "$HOME/.floatlight/floatlight-sync",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://EXTENSION_ID/"
  ]
}
```
