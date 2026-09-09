// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { i18n } from '../src/runtime/i18n'

const { getUserCardMock, followUserMock } = vi.hoisted(() => ({
  getUserCardMock: vi.fn(),
  followUserMock: vi.fn(),
}))

vi.mock('@/runtime/api', () => ({
  getUserCard: getUserCardMock,
  followUser: followUserMock,
}))

import UserCard from '../src/site/components/UserCard.vue'
import { broadcastFollowChange, getKnownFollowState, resetFollowState } from '../src/runtime/follow-state'
import type { UserCardPayload } from '@gooseforum/client'

const t = (key: string) => i18n.global.t(key)

function makeCard(overrides: Partial<UserCardPayload> = {}): UserCardPayload {
  return {
    userId: 42,
    username: 'alice',
    nickname: 'Alice',
    avatarUrl: '/static/pic/default-avatar.webp',
    profileCoverUrl: '',
    bio: '',
    signature: '',
    websiteName: '',
    website: '',
    prestige: 0,
    externalInformation: {},
    isAdmin: false,
    topicCount: 1,
    replyCount: 2,
    likeReceivedCount: 3,
    likeGivenCount: 0,
    followerCount: 10,
    followingCount: 0,
    collectionCount: 0,
    isOnline: false,
    isFollowing: false,
    isSelf: false,
    badges: [],
    wornBadge: null,
    lastActiveTime: '2026-09-09T00:00:00Z',
    createdAt: '2026-01-01T00:00:00Z',
    isAccountClosed: false,
    ...overrides,
  }
}

function showCard(userId = 42) {
  const target = document.createElement('a')
  document.body.appendChild(target)
  window.dispatchEvent(
    new CustomEvent('goose:user-card-show', {
      detail: { user: { id: userId, username: 'alice', avatarUrl: '' }, target },
    }),
  )
}

function followButton(): HTMLButtonElement | null {
  const buttons = Array.from(document.body.querySelectorAll('button'))
  return buttons.find((b) => [t('userCard.follow'), t('userCard.following')].includes(b.textContent?.trim() || '')) ?? null
}

function followerStatValue(): string {
  const cells = Array.from(document.body.querySelectorAll('.grid.grid-cols-4 > div'))
  const cell = cells.find((c) => c.textContent?.includes(t('userCard.stats.followers')))
  return cell?.querySelector('div')?.textContent?.trim() ?? ''
}

async function flushAll() {
  await flushPromises()
  await flushPromises()
}

let wrapper: ReturnType<typeof mount> | undefined

async function mountCard() {
  wrapper = mount(UserCard, { global: { plugins: [i18n] } })
  await flushPromises()
}

describe('UserCard 关注状态（issue #593）', () => {
  beforeEach(() => {
    resetFollowState()
    getUserCardMock.mockReset()
    followUserMock.mockReset()
  })

  afterEach(() => {
    wrapper?.unmount()
    wrapper = undefined
    document.body.innerHTML = ''
    vi.useRealTimers()
  })

  test('toggle 成功后回源刷新：按钮态以服务端为准，粉丝数更新并写回缓存', async () => {
    getUserCardMock.mockResolvedValueOnce(makeCard())
    getUserCardMock.mockResolvedValueOnce(makeCard({ isFollowing: true, followerCount: 11 }))
    followUserMock.mockResolvedValueOnce(true)
    await mountCard()
    showCard()
    await flushAll()
    expect(followButton()?.textContent?.trim()).toBe(t('userCard.follow'))

    followButton()!.click()
    await flushAll()

    expect(followUserMock).toHaveBeenCalledWith(42, false)
    expect(getUserCardMock).toHaveBeenCalledTimes(2)
    expect(followButton()?.textContent?.trim()).toBe(t('userCard.following'))
    expect(getKnownFollowState(42)).toBe(true)

    // TTL 内重开命中缓存（且共享状态已纠正），不重复拉取
    window.dispatchEvent(new CustomEvent('goose:page'))
    showCard()
    await flushAll()
    expect(getUserCardMock).toHaveBeenCalledTimes(2)
    expect(followButton()?.textContent?.trim()).toBe(t('userCard.following'))
  })

  test('toggle 失败：内联展示错误且状态不变，不再静默吞错', async () => {
    getUserCardMock.mockResolvedValueOnce(makeCard())
    followUserMock.mockRejectedValueOnce(new Error('关注操作失败'))
    await mountCard()
    showCard()
    await flushAll()

    followButton()!.click()
    await flushAll()

    expect(followButton()?.textContent?.trim()).toBe(t('userCard.follow'))
    expect(getUserCardMock).toHaveBeenCalledTimes(1)
    const alert = document.body.querySelector('[role="alert"]')
    expect(alert?.textContent).toContain('关注操作失败')
  })

  test('goose:follow-changed 广播即时纠正已打开卡片与缓存（跨 surface 同步）', async () => {
    getUserCardMock.mockResolvedValueOnce(makeCard())
    await mountCard()
    showCard()
    await flushAll()
    expect(followButton()?.textContent?.trim()).toBe(t('userCard.follow'))

    broadcastFollowChange(42, true)
    await flushAll()
    expect(followButton()?.textContent?.trim()).toBe(t('userCard.following'))

    // 缓存条目已同步：TTL 内重开不再拉取
    window.dispatchEvent(new CustomEvent('goose:page'))
    showCard()
    await flushAll()
    expect(followButton()?.textContent?.trim()).toBe(t('userCard.following'))
    expect(getUserCardMock).toHaveBeenCalledTimes(1)
  })

  test('缓存命中后超过 TTL 触发 stale-while-revalidate，旧态被服务端纠正', async () => {
    vi.useFakeTimers({ toFake: ['Date'] })
    getUserCardMock.mockResolvedValueOnce(makeCard({ isFollowing: false, followerCount: 10 }))
    await mountCard()
    showCard()
    await flushAll()
    expect(followButton()?.textContent?.trim()).toBe(t('userCard.follow'))
    expect(getUserCardMock).toHaveBeenCalledTimes(1)

    window.dispatchEvent(new CustomEvent('goose:page'))
    vi.setSystemTime(Date.now() + 61_000)
    getUserCardMock.mockResolvedValueOnce(makeCard({ isFollowing: true, followerCount: 11 }))
    showCard()
    await flushAll()

    expect(getUserCardMock).toHaveBeenCalledTimes(2)
    expect(followButton()?.textContent?.trim()).toBe(t('userCard.following'))
    expect(followerStatValue()).toBe('11')
  })
})
