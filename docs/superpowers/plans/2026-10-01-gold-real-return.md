# 黄金真实收益 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 按已确认原型在 iOS 记金中实现 P0 真实收益和完整持仓交互。
**Architecture:** SwiftData 增量可选/默认字段，统一纯逻辑 GoldReturnCalculator。页面使用同一行情口径，提醒状态随持仓持久化，本地通知由前台行情驱动。
**Tech Stack:** Swift 6、SwiftUI、SwiftData、Swift Testing、UserNotifications。
**Spec:** docs/gold-real-return-prd.md + docs/gold-real-return-ui-prototype.md（已确认）。

## Global Constraints
- iOS 17+，零第三方依赖；保留现有底部导航、GoldTheme。
- 旧记录继续可用，购买日期精确时点保持现有行为。
- 所有结果标记估算，默认规则透明，行情依据沿用 GoldMarketBasis。
- Widget、多渠道模板、收益曲线属于 P1，不在本轮实现。

## Review Focus
- 手填总价覆盖工费推导，不能重复计费；日历和部分卖出成本守恒。
- 无效/非有限数字、零重量、100%折价不产生看似有效的收益。
- 无行情仍显示成本和保本价，旧行情标非实时且暂停提醒。
- 阈值初始已达不通知，穿越、冷却、迟到报价、异常跳变受保护。
- 计算器转持仓保留输入；编辑不覆盖处置信息；金额隐藏涵盖全部金额。

### Task 1: 计算和持仓数据
**Files:** GoldReturnCalculator.swift、HoldingDraft.swift、HoldingRecord.swift、HoldingDisposal.swift、HoldingsStats.swift、HoldingsSelection.swift、HoldingCalendarLogic.swift、GoldReturnTests.swift。
**Interfaces:** `GoldReturnInput` → `GoldReturnCalculator.calculate(_:referencePrice:) -> GoldReturnResult?`；`HoldingRecord.returnInput`、`totalPurchaseCost`；`HoldingDraft.input`。
- [x] 写测试：30g 总价25800；30g 单价780+80/g工费，扣8保本868；纯度/折价/费用与反推；异质规则汇总；无行情/坏输入。
- [x] 运行定向 make test，确认缺失 API 失败；实现纯逻辑与轻量字段。
- [x] 测试旧记录、磁盘回读、部分赠卖所有成本守恒、日历及筛选真实收益，运行全部测试。

### Task 2: 核心 UI 与计算器
**Files:** AddHoldingSheet.swift、HoldingsView.swift、HoldingDetailView.swift、GoldReturnComponents.swift、GoldCalculatorSheet.swift、GoldScenarioSheet.swift、HoldingsViewModel.swift。
**Interfaces:** 页面全部消费 Task 1 输入/结果，计算器以 `HoldingDraft` 带入新增。
- [x] 快速录入总价/单价模式、工费模式、高级参数、实时保本反馈，支持编辑。
- [x] 首页核心预计到手、保本、今日变化、快捷操作及单笔真实收益，复用隐私存储。
- [x] 详情、计算依据、情景数字/Slider/六个快捷价格点、保存为持仓及现有卖出。
- [x] 新增表单转换/编辑回归测试；生成工程、编译、模拟器截图目视验证。

### Task 3: 持仓事件提醒
**Files:** HoldingAlert.swift、HoldingAlertMonitor.swift、HoldingAlertSheet.swift、SumlyApp.swift、HoldingAlertTests.swift。
**Interfaces:** Codable alerts 存 `HoldingRecord.alertsJSON`；纯函数 evaluate 接有效报价更新状态；通知边界协议可注入测试。
- [x] 写并运行失败测试：四类阈值，主动启用、穿越、冷却、迟到/过时行情、异常跳价。
- [x] 实现持久化提醒与前台轮询通知；用户授权被拒时保留关闭并显示设置提示；修改规则重新建立基线。
- [x] 通知失败不消耗触发状态；持仓卖出/删除清理 pending；前后台取消与行情口径切换隔离。

### Task 4: 验证与交付
- [x] 完整 make test + make build；SwiftData 旧 schema 实际磁盘迁移；模拟器核心页面与隐私截图。
- [x] 阅读完整 diff 做独立审查，修复实质问题并补回归测试。
- [x] 更新 iOS README 描述默认模型、估算/提醒边界和实测结果；保留所有用户原有文件。

## Implementation decisions
- 默认回收采用当前选择的市场参考价，扣减/折价/固定费用为 0；透明展示这不是渠道报价。
- 老记录纯度按100%估算，新表单默认9999；手填总成本是最终现金支出，工费不再加一次。
- 回收单价及到手下限为0；组合保本以统一引擎单调求根，避免异质规则平均导致错误。
- 本轮在当前仓库的新功能分支执行，保留未跟踪的需求/原型文件；不提交用户文件、不推送。

## Verification record (2026-10-01)
- 原始套件132项通过；首轮实现146项通过；独立审查后151项通过。
- 实际旧 schema 磁盘迁移并二次打开已通过；保留旧账本、日期、卖出收入及新增提醒状态。
- 独立审查发现的5项问题已修复：表单冷却状态倒退、关闭提醒被隐藏无效字段阻断、发送中取消、旧基线无法恢复、数值派生溢出。
- 模拟器已目视检查首页、详情、计算依据、情景保本快捷点、计算器30g×780+80/g=25800、自动带入并保存、金额隐藏、四类提醒。
- 本轮不测试真实通知授权/系统投递，不修改后端、不进行后台推送部署；通知边界通过可控异步 fake 验证提交失败和取消。
