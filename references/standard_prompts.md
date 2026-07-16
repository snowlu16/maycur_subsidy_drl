# 生成每刻补贴 DRL 规则脚本：标准提问提示词（Prompt 模板手册）

> 在使用 AI（或向顾问/研发沟通）自动生成每刻差旅补贴及费用规则脚本（Drools/Mvel 语法）时，**提示词越结构化、要素越齐全，生成的代码一次性跑通率越接近 100%**。
> 本手册提供从“极简日常开发”到“复杂场景定制”的标准提示词模板，可直接复制粘贴使用！

---

## 一、 极简通用填空版 Prompt (适合日常快速生成 80% 场景)

在让 AI 编写或修改补贴规则时，直接复制以下模板并填空替换括号中的内容：

```markdown
请作为每刻报销（Maycur）规则引擎（Drools/Mvel）专家，根据我提供的《maycur_subsidy_drl》开发规范，帮我编写一份可直接在生产运行的差旅补贴 `.drl` 脚本。

### 业务规则与参数配置
1. **人员范围**：【报销人 + 参与人/同行人】 / 【仅报销人】 / 【仅同行人】
2. **计算模式与分界**：【全天按天计算，不区分12:00】 / 【半天计算，出发日/返回日以 12:00 为上下午分界，重叠跳过】
3. **输出汇总方式**：【按单段行程汇总，一个行程生成一条明细】 / 【按天每天各自独立生成一条明细】 / 【按天所有人合并为一条】
4. **后台配置参数**：
   - 补贴标准编码 (`bizCode`)：【例如：ALLOWANCE_TRAFFIC_STD】
   - 生成的报销明细费用类型编码 (`feeCode`)：【例如：ALLOWANCE_TRAFFIC_FEE】
5. **是否需要扣减/关联判定**：
   - 【无额外扣减，按标准发放】 / 【若单据内包含打车费（费用编码：BT）/住宿费（费用编码：HOTEL），则对应日期的补贴金额折半（乘 0.5）】

### 代码强制遵守规范 (请严格执行)
1. 报销人和同行人必须分开不同的 Rule/Salience 独立计算（例如报销人 `salience 20`，参与人 `salience 10`，必须用 `TravelRoute` 上的 `$partnerAllowanceStandardInfos` 解构给参与人，不能和报销人的标准对象混淆）；
2. 算出的明细必须强挂行程 Code：调用 `allowanceResult.setTravelRouteCode($travelRouteCode)` 并在有目的地时调用 `setConsumeLocation($destination)`；
3. **严禁在金额为 0 时调用 `insert(allowanceResult)`**！必须使用 `if (amount.compareTo(BigDecimal.ZERO) == 1)` 判断保护；
4. 内部所有时间操作务必严格使用 **Joda-Time (`com.maycur.util.DateTime`)** API（如 `plusDays(1)`、`compareTo`），严禁使用 Java 8 LocalDate 方法；
5. 请给出完整开箱即用的 Mvel `package rules;` 代码，并在关键地方给出简明中文注释。
```

---

## 二、 复杂/高阶定制场景标准结构化 Prompt (适合带有考勤、连续扣减、多标准、自定义表单等)

当业务涉及到复杂扣减或高级判定逻辑时，建议使用以下 **XML 结构化高级提示词**：

```markdown
请严格按照每刻报销底层 Drools 规则引擎（Mvel 语法、Joda-Time 时间处理）的标准与技巧，为以下复杂的定制补贴场景生成无错、健壮的 DRL 源码：

<SubsidyRequirements>
  <ScenarioName>【请填写：例如“国内外双套标准+有招待费自动扣减+同行人每天单独成条”】</ScenarioName>
  
  <TargetUsers>
    <!-- 可选值：BOTH (报销人+参与人) / ONLY_REIMBURSER (仅报销人) / ONLY_PARTNER (仅同行人) -->
    <Role>BOTH</Role>
    <!-- 若包含同行人，是否所有人合并算一条费用还是每人每天独立一条？ -->
    <PartnerSummaryMode>每人每天独立生成一条 AllowanceResult</PartnerSummaryMode>
  </TargetUsers>

  <TimeAndSummaryDimension>
    <!-- 基础计算维度：ALL_DAY (全天1天1个基本单位) / HALF_DAY (以12点分界的半天) -->
    <TimeGranularity>ALL_DAY</TimeGranularity>
    <!-- 最终输出维：PER_TRIP (按单段行程区间 $startDate-$endDate 汇总1条) / PER_DAY (按自然天每天生成1条) -->
    <SummaryOutput>PER_DAY</SummaryOutput>
  </TimeAndSummaryDimension>

  <ConfigCodes>
    <BizCode>TRAFFIC_ALLOWANCE_STD</BizCode>
    <FeeCode>TRAFFIC_FEE</FeeCode>
    <!-- 如有多套标准（如国内/国外，或者高管/员工），请在此列出切分条件和对应 bizCode -->
    <ConditionStandards>
      <Standard condition="目的地包含国内字符串 domestic">TRAFFIC_ALLOWANCE_STD_CN</Standard>
      <Standard condition="目的地包含国外字符串 abroad">TRAFFIC_ALLOWANCE_STD_INTL</Standard>
    </ConditionStandards>
  </ConfigCodes>

  <DeductionAndSpecialRules>
    <!-- 1. 关联费用扣减原则： -->
    <Rule type="ExpenseDeduction">
      当关联单据/报销单明细列表 Reimburse($expenses : expenses) 中，存在费用编码为 "ENTERTAINMENT_FEE" (招待费) 的消费时，对比其费用明细日期 (consumeDate)，若该自然日曾申报了招待费，则当天补贴折半 (multiply(BigDecimal.valueOf(0.5)))。
    </Rule>
    <!-- 2. 行程连续跨段去重原则： -->
    <Rule type="ContinuousTrip">
      同一出差人连续相邻多段行程跨越计算时，依靠 salience 25 的预处理逻辑对日期去重，避免拆分多条跨天行程时的末日与次日首日重复算钱。
    </Rule>
  </DeductionAndSpecialRules>
</SubsidyRequirements>

<CriticalConstraints>
1. 若涉及到多套 `bizCode` 切换或跨段去重，必须使用 `salience 30` 初始化参数 Map、`salience 25` 进行行程预排重收集，然后 `salience 20` 算报销人、`salience 10` 算参与人；
2. 绝对遵守金额大于 0 才 `insert(allowanceResult)`，切勿在 amount 为 0 或负数时 insert；
3. 输出完整的 `package rules; ...` 脚本，不准省略局部逻辑或输出占位符注释。
</CriticalConstraints>
```

---

## 三、 四大高频实战场景 —— Copy-Paste 提问指令卡

### 场景卡片 1：报销人与参与人全天行程汇总（最最常用）
> **提问直接复制：**
> “帮我生成一份每刻报销 DRL 补贴脚本：
> 计算目标包含报销人与行程同行参与人；按全天自然日计算（使用 `isDayOverlap` 去重逻辑）；最终按每一段行程的开始与结束区间合并汇总输出一条补贴费用明细；
> 后台补贴标准编码为 `TRAFFIC_ALL_DAY`，生成的报销费用编码为 `TRAFFIC_ALL_FEE`；要求报销人与参与人使用不同的 salience 和独立的 standard info 字段解构，金额大于 0 且必须关联 `$travelRouteCode`。”

### 场景卡片 2：上下午半天判断 + 有打车费则减半
> **提问直接复制：**
> “帮我生成一份每刻报销 DRL 补贴脚本：
> 按半天模式计算（自带 `isDayHalveOrOverlap` 函数判断出发返回日 12:00 边界）；适用于报销人及同行参与人；最终按天或行程汇总均可；
> 核心扣减逻辑：同时在 `Reimburse($expenses : expenses)` 中获取本次报销单的其他费用明细，如果存在费用类型编码为 `BT` (打车费) 的明细，且打车费明细的消费日期 (`consumeDate`) 与当前在算补贴的日期在同一天，则当天对应的该笔补贴金额自动乘以 `0.5`（折半）；如果上下午各打了一次车，不重复折半（或最多折半一次）。请给出完整严谨的代码。”

### 场景卡片 3：遇到自定义表单选择字段（如是否派车/职级）
> **提问直接复制：**
> “请解答并生成代码：我的每刻补贴需求是‘员工行程上有个下拉选项【是否派车】，选【是】补贴为0元，选【否】补贴为80元/天’。请告诉我：
> 1) 在 DRL 代码中是否需要写 `customFormValues` 判断逻辑？
> 2) 为什么根据官方语雀 Q&A 手册，把【是否派车】配置在系统补贴标准表的行维度上就可以直接匹配？
> 3) 顺便给我一份配合该行维度直接计算的最干净、轻量级的全天行程补贴 DRL 脚本模板！”

### 场景卡片 4：连续多段行程末日扣减去尾
> **提问直接复制：**
> “帮我生成一份高阶每刻补贴规则脚本：
> 业务规范是‘员工一次出差分为了段行程（例如杭州->南京 2月1日-2月3日，南京->北京 2月3日-2月5日），两段连续接驳，但我们的报销标准要求：如果是连续行程，两段接驳的 2月3日 只能发一次钱，而且无论是多段连续还是一段行程，整个出差周期的最后一天（也就是回归日 2月5日）要扣掉不发补贴（只补中间天数）’。请利用 `DateListTravel` 或 `plusDays` 排序去重技巧，给我完整的 DRL 规则实现。”
