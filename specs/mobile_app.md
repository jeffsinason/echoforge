---
title: "EchoForge Mobile App"
version: "0.1"
status: draft
project: EchoForge
created: 2026-01-03
updated: 2026-01-03
github_issue: 22
---

# EchoForge Mobile App Specification

> **Status:** Draft - Planning Phase
> **GitHub Issue:** [#22](https://github.com/jeffsinason/EchoForgeX/issues/22)

## 1. Overview

### 1.1 Purpose

Native mobile application for iOS and Android that provides:
- Real-time streaming chat with AI agents
- Mission management and approval workflows
- Push notifications for async events
- Offline support

### 1.2 Key Requirements

| Requirement | Priority | Notes |
|-------------|----------|-------|
| Single codebase (iOS + Android) | **Must Have** | Primary constraint |
| Real-time streaming responses | **Must Have** | Core functionality |
| Markdown rendering | **Must Have** | Agent responses use markdown |
| Push notifications | **Must Have** | Mission approvals, completions |
| Offline message queue | Should Have | Graceful degradation |
| Biometric authentication | Should Have | Security enhancement |

### 1.3 Framework Decision: Expo (React Native)

**Recommendation: Use Expo** with managed workflow initially.

#### Rationale

| Factor | Assessment |
|--------|------------|
| Single codebase | ✅ JavaScript/TypeScript for both platforms |
| Prior experience | ✅ Team has used Expo before |
| Streaming support | ✅ Libraries available (see Section 3) |
| Push notifications | ✅ Expo Notifications built-in |
| Development speed | ✅ Hot reload, Expo Go for testing |
| OTA updates | ✅ Update JS without app store review |
| Community/ecosystem | ✅ Large, active community |

---

## 2. Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    EchoForge Mobile App                      │
│                        (Expo/RN)                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Screens   │  │ Components  │  │    Navigation       │  │
│  ├─────────────┤  ├─────────────┤  ├─────────────────────┤  │
│  │ Chat        │  │ MessageBubble│  │ React Navigation    │  │
│  │ Missions    │  │ MarkdownView│  │ Tab + Stack         │  │
│  │ Settings    │  │ ApprovalCard│  │                     │  │
│  │ Auth        │  │ MissionCard │  │                     │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│                      State Management                        │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                    Zustand Store                        ││
│  │  ├── conversations: Map<id, Conversation>               ││
│  │  ├── missions: Map<id, Mission>                         ││
│  │  ├── auth: { token, user, isAuthenticated }             ││
│  │  └── ui: { theme, notifications }                       ││
│  └─────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│                      Services Layer                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ ChatService  │  │ AuthService  │  │ PushService  │       │
│  │ (WebSocket)  │  │ (REST)       │  │ (Expo)       │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
├─────────────────────────────────────────────────────────────┤
│                      Local Storage                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ SecureStore  │  │ AsyncStorage │  │ SQLite       │       │
│  │ (tokens)     │  │ (settings)   │  │ (messages)   │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    EchoForge Backend                         │
│  ┌──────────────┐              ┌──────────────┐             │
│  │ Agent API    │              │   Hub API    │             │
│  │ (WebSocket)  │              │   (REST)     │             │
│  │ Port 8004    │              │   Port 8003  │             │
│  └──────────────┘              └──────────────┘             │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Screen Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Splash    │────▶│    Auth     │────▶│    Main     │
│   Screen    │     │   (Login)   │     │   (Tabs)    │
└─────────────┘     └─────────────┘     └──────┬──────┘
                                               │
                    ┌──────────────────────────┼──────────────────────────┐
                    │                          │                          │
                    ▼                          ▼                          ▼
             ┌─────────────┐           ┌─────────────┐           ┌─────────────┐
             │    Chat     │           │  Missions   │           │  Settings   │
             │    Tab      │           │    Tab      │           │    Tab      │
             └──────┬──────┘           └──────┬──────┘           └─────────────┘
                    │                          │
                    ▼                          ▼
             ┌─────────────┐           ┌─────────────┐
             │Conversation │           │  Mission    │
             │   Detail    │           │   Detail    │
             └─────────────┘           └─────────────┘
```

---

## 3. Technical Implementation

### 3.1 Streaming Protocol Decision

**Recommendation: WebSocket** (not SSE)

#### Research Findings

| Protocol | Expo Support | Notes |
|----------|--------------|-------|
| SSE | ⚠️ Issues | [Known Expo bug](https://github.com/expo/expo/issues/27526) with CdpInterceptor blocking SSE on Android |
| WebSocket | ✅ Native | Built-in support, well-documented best practices |

#### SSE Workaround (if needed)
The [react-native-sse](https://github.com/binaryminds/react-native-sse) library can work around Expo's SSE issues, but WebSocket is more reliable.

#### WebSocket Best Practices

Based on [industry best practices](https://medium.com/@tusharkumar27864/best-practices-of-using-websockets-real-time-communication-in-react-native-projects-89e749ba2e3f):

1. **Singleton Pattern** - Single connection instance across app
2. **Automatic Reconnection** - Handle network changes gracefully
3. **State via Context/Zustand** - Don't pass socket through props
4. **Use wss://** - Always encrypt WebSocket traffic
5. **Token in handshake** - Authenticate on connection

### 3.2 Required Backend Changes

**New WebSocket endpoint needed on Agent:**

```
ws://agent:8004/v1/chat/ws
```

| Event | Direction | Payload |
|-------|-----------|---------|
| `connect` | Client→Server | `{ token, conversation_id? }` |
| `message` | Client→Server | `{ content, conversation_id }` |
| `message_start` | Server→Client | `{ conversation_id, message_id }` |
| `content_delta` | Server→Client | `{ delta }` |
| `tool_use` | Server→Client | `{ tool, inputs }` |
| `tool_result` | Server→Client | `{ tool, result }` |
| `message_end` | Server→Client | `{ tokens_used }` |
| `error` | Server→Client | `{ code, message }` |

### 3.3 Markdown Rendering

**Recommendation: [streamdown-rn](https://libraries.io/npm/streamdown-rn)**

Specifically designed for streaming markdown in Expo - ideal for LLM responses.

**Alternative:** [react-native-markdown-display](https://github.com/jonasmerlin/react-native-markdown-display) - More mature, 100% CommonMark compatible.

#### Implementation

```typescript
// components/StreamingMarkdown.tsx
import { StreamdownRN } from 'streamdown-rn';

export function StreamingMarkdown({ content, isStreaming }) {
  return (
    <StreamdownRN
      content={content}
      streaming={isStreaming}
      components={{
        code: CustomCodeBlock,
        heading: CustomHeading,
      }}
    />
  );
}
```

### 3.4 Push Notifications

Use **Expo Notifications** (built-in):

```typescript
// services/push.ts
import * as Notifications from 'expo-notifications';

export async function registerForPushNotifications() {
  const { status } = await Notifications.requestPermissionsAsync();
  if (status !== 'granted') return null;

  const token = await Notifications.getExpoPushTokenAsync();

  // Register token with Hub
  await hubApi.registerPushToken(token.data);

  return token;
}
```

**Notification Types:**

| Type | Trigger | Action |
|------|---------|--------|
| Mission Approval | `mission_ask_user` called | Open mission detail |
| Mission Complete | Mission status → completed | Show summary |
| Email Reply | Reply received for tracked email | Open chat |

### 3.5 State Management

**Recommendation: Zustand** (lightweight, TypeScript-friendly)

```typescript
// store/index.ts
import { create } from 'zustand';
import { persist } from 'zustand/middleware';

interface AppState {
  // Auth
  token: string | null;
  user: User | null;

  // Conversations
  conversations: Map<string, Conversation>;
  activeConversationId: string | null;

  // Missions
  missions: Map<string, Mission>;
  pendingApprovals: Approval[];

  // Actions
  setToken: (token: string) => void;
  addMessage: (convId: string, message: Message) => void;
  updateMission: (mission: Mission) => void;
}

export const useStore = create<AppState>()(
  persist(
    (set, get) => ({
      // ... implementation
    }),
    { name: 'echoforge-storage' }
  )
);
```

### 3.6 Offline Support

```
┌─────────────────────────────────────────────┐
│              Offline Strategy               │
├─────────────────────────────────────────────┤
│                                             │
│  1. Message Queue                           │
│     - Store pending messages in SQLite      │
│     - Retry on reconnection                 │
│     - Show "pending" indicator              │
│                                             │
│  2. Conversation Cache                      │
│     - Cache last N messages per conv        │
│     - Fetch delta on reconnect              │
│                                             │
│  3. Mission Cache                           │
│     - Cache active missions                 │
│     - Queue approval responses              │
│     - Sync on reconnect                     │
│                                             │
└─────────────────────────────────────────────┘
```

---

## 4. Screens

### 4.1 Chat Screen

```
┌─────────────────────────────────────┐
│ ← Conversations    Personal Agent ⚙️│
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐    │
│  │ Hi! How can I help you      │    │
│  │ today?                      │    │
│  └─────────────────────────────┘    │
│                                     │
│         ┌─────────────────────────┐ │
│         │ Schedule a meeting with │ │
│         │ Sarah next week        │ │
│         └─────────────────────────┘ │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ I'll help you schedule that │    │
│  │ meeting. Let me check your  │    │
│  │ calendar...                 │    │
│  │                             │    │
│  │ **Available slots:**        │    │
│  │ - Tuesday 2pm              │    │
│  │ - Wednesday 10am           │    │
│  │                             │    │
│  │ ```                         │    │
│  │ Checking Sarah's calendar...│    │
│  │ ```                         │    │
│  │ ● ● ●                       │    │ ← streaming indicator
│  └─────────────────────────────┘    │
│                                     │
├─────────────────────────────────────┤
│ ┌─────────────────────────────┐ ▲  │
│ │ Type a message...           │ │  │
│ └─────────────────────────────┘    │
└─────────────────────────────────────┘
```

### 4.2 Missions Screen

```
┌─────────────────────────────────────┐
│         Missions              Filter│
├─────────────────────────────────────┤
│                                     │
│ ⚠️ NEEDS ATTENTION (2)              │
│ ┌─────────────────────────────────┐ │
│ │ 🔴 Schedule PTA meeting         │ │
│ │    Waiting for your approval    │ │
│ │    ├─ ✅ Check calendar         │ │
│ │    ├─ ✅ Email Sarah            │ │
│ │    └─ 🛑 Select time slot       │ │
│ │                     [Respond →] │ │
│ └─────────────────────────────────┘ │
│                                     │
│ 🔄 IN PROGRESS (3)                  │
│ ┌─────────────────────────────────┐ │
│ │ 🟡 Research competitors         │ │
│ │    3/5 tasks complete           │ │
│ │    ░░░░░░░░░░░░░░░░ 60%        │ │
│ └─────────────────────────────────┘ │
│                                     │
│ ✅ RECENTLY COMPLETED               │
│ ┌─────────────────────────────────┐ │
│ │ ✅ Book restaurant - Yesterday  │ │
│ └─────────────────────────────────┘ │
│                                     │
├─────────────────────────────────────┤
│    💬 Chat    📋 Missions    ⚙️     │
└─────────────────────────────────────┘
```

### 4.3 Approval Modal

```
┌─────────────────────────────────────┐
│                                     │
│         Approval Required           │
│                                     │
│  Schedule meeting with Sarah        │
│                                     │
│  I found these available times:     │
│                                     │
│  ┌─────────────────────────────────┐│
│  │ 📅 Tuesday, Jan 7 at 2:00 PM   ││
│  │    Both calendars free          ││
│  │                      [Select]   ││
│  └─────────────────────────────────┘│
│                                     │
│  ┌─────────────────────────────────┐│
│  │ 📅 Wednesday, Jan 8 at 10:00 AM││
│  │    Both calendars free          ││
│  │                      [Select]   ││
│  └─────────────────────────────────┘│
│                                     │
│  ┌─────────────────────────────────┐│
│  │ None work - suggest others      ││
│  └─────────────────────────────────┘│
│                                     │
│           [Cancel Mission]          │
│                                     │
└─────────────────────────────────────┘
```

---

## 5. Development Phases

### Phase 1: Foundation
- [ ] Initialize Expo project with TypeScript
- [ ] Set up navigation (React Navigation)
- [ ] Implement auth flow (login, token storage)
- [ ] Create basic UI components

### Phase 2: Chat Core
- [ ] Implement WebSocket service (singleton)
- [ ] Build chat screen with message list
- [ ] Add streaming markdown rendering
- [ ] Handle reconnection logic

### Phase 3: Missions
- [ ] Mission list screen
- [ ] Mission detail screen
- [ ] Approval modal/flow
- [ ] Push notification handling

### Phase 4: Polish
- [ ] Offline support
- [ ] Error handling & retry logic
- [ ] Performance optimization
- [ ] Accessibility

### Phase 5: Release
- [ ] App store assets (icons, screenshots)
- [ ] Beta testing (TestFlight, Play Console)
- [ ] Production deployment

---

## 6. Dependencies

### Core
```json
{
  "expo": "~50.0.0",
  "react": "18.2.0",
  "react-native": "0.73.x",
  "typescript": "^5.0.0"
}
```

### Navigation
```json
{
  "@react-navigation/native": "^6.x",
  "@react-navigation/bottom-tabs": "^6.x",
  "@react-navigation/stack": "^6.x"
}
```

### State & Storage
```json
{
  "zustand": "^4.x",
  "expo-secure-store": "~12.x",
  "@react-native-async-storage/async-storage": "^1.x"
}
```

### Streaming & Markdown
```json
{
  "streamdown-rn": "^0.2.x",
  "react-native-markdown-display": "^7.x"
}
```

### Notifications
```json
{
  "expo-notifications": "~0.27.x"
}
```

---

## 7. Backend Requirements

### 7.1 New WebSocket Endpoint

The Agent needs a WebSocket endpoint to support mobile streaming:

**File:** `echoforge-agent/src/api/routes/websocket.py` (new)

See Issue #22 for detailed requirements.

### 7.2 Push Notification Integration

The Hub needs endpoints for push token registration:

| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/api/v1/devices` | Register push token |
| DELETE | `/api/v1/devices/{id}` | Unregister device |
| POST | `/api/internal/notifications/send` | Send push (internal) |

---

## 8. Open Questions

1. **Minimum OS versions?**
   - iOS 14+ recommended for Expo SDK 50
   - Android API 23+ (Android 6.0)

2. **App store accounts?**
   - Apple Developer Program ($99/year)
   - Google Play Console ($25 one-time)

3. **Analytics/crash reporting?**
   - Expo offers built-in, or use Sentry/Firebase

4. **Deep linking?**
   - Support `echoforge://` scheme for notifications?

---

## 9. Resources

### Research Sources
- [Expo SSE Issue #27526](https://github.com/expo/expo/issues/27526)
- [react-native-sse](https://github.com/binaryminds/react-native-sse)
- [WebSocket Best Practices](https://medium.com/@tusharkumar27864/best-practices-of-using-websockets-real-time-communication-in-react-native-projects-89e749ba2e3f)
- [streamdown-rn](https://libraries.io/npm/streamdown-rn)
- [react-native-markdown-display](https://github.com/jonasmerlin/react-native-markdown-display)
- [Expo Notifications](https://docs.expo.dev/push-notifications/overview/)

---

*End of Specification*
