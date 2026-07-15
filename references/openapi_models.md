# OpenAPI NG 每刻补贴规则引擎核心数据对象字典 (Data Dictionary)

本文档根据每刻官方最新开发文档（`https://openapi-ng.maycur.com/allowance/allowance.html`）梳理并精确核实。在编写或调试 `.drl` 补贴脚本时，可通过本速查表确认各个 Fact 对象及子对象的完整属性字典与返回类型。所有日期字段 `DateTime` 均指 `org.joda.time.DateTime`。

---

## 1. 单据级事实对象 (`Reimburse`)

当由报销单或出差申请单触发补贴计算时，`Reimburse` 会直接以事实对象 (`Fact`) 形式存在于内存中。

| 参数名称 | 类型 | 描述与用途 |
| :--- | :--- | :--- |
| `entCode` | `String` | 企业编码 |
| `formTypeBizCode` | `String` | 单据小类业务编码 |
| `subsidiaryBizCode` | `String` | 业务实体业务编码 |
| `legalEntityBizCode` | `String` | 公司抬头业务编码 |
| `reimEmployee` | `Employee` | 报销人（提单人）信息对象 |
| `expenses` | `List<Expense>` | 费用明细列表 (`List<Expense>`) |
| `travelRoutes` | `List<TravelRoute>` | 行程明细列表 (`List<TravelRoute>`) |
| `customFormValues` | `List<CustomFormValue>` | 单据表头自定义表单字段信息 |
| `collectionCcy` | `String` | 收款币种 (如 `"CNY"`) |
| `baseCcy` | `String` | 本币币种 (如 `"CNY"`) |
| `submittedAt` | `DateTime` | 最近提单时间 |
| `firstSubmittedAt` | `DateTime` | 第一次提单时间 |
| `travelPartnerInfo` | `TravelPartnerInfo` | 单据级参与人/同行人信息组 |
| `ruleScheduleValue` | `RuleScheduleValue` | 节假日信息列表 (配合 `allowanceService.isSchedule` 判断节假日/工作日) |

---

## 2. 员工信息对象 (`Employee`)

| 参数名称 | 类型 | 描述与用途 |
| :--- | :--- | :--- |
| `userCode` | `String` | 员工唯一编码 (在 `dateMap` 或两套标准计算中常作为 key) |
| `name` | `String` | 员工姓名 |
| `employeeId` | `String` | 员工工号 |
| `residences` | `List<Residence>` | 员工常驻地列表 (`placeFullCode` 包含行政编码如 `"330000-330100-330106"`) |
| `customFormValues` | `List<CustomFormValue>` | 员工档案上的自定义表单字段 |
| `classPositionBizCode` | `String` | 职级业务编码 |
| `hireDate` | `DateTime` | 入职日期 |
| `gender` | `GenderEnum` | 性别枚举：`MAN` (男) / `WOMAN` (女) |
| `rtRouteList` | `List<RTRoute>` | 员工所属部门树与汇报线信息 |

### 附：`RTRoute`（部门汇报线信息）
- `departmentBizCode`: `String` - 部门业务编码
- `supervisorEmployeeId`: `String` - 直接上级工号
- `positionBizCode`: `String` - 职位业务编码

### 附：`Residence`（常驻地对象）
- `placeFullCode`: `String` - 每刻标准地址编码 (如 `"330000-330100-330106"` 浙江省-杭州市-西湖区)
- `includeChildPlace`: `String` - 是否包含下级行政区

---

## 3. 费用明细对象 (`Expense`)

可以在 `.drl` 中通过 `Reimburse($expenses : expenses)` 取出，常用于**依据关联费用（如住宿费、打车费）触发餐补扣减或计算折半**。

| 参数名称 | 类型 | 描述与用途 |
| :--- | :--- | :--- |
| `code` | `String` | 费用行编码（唯一编码） |
| `typeBizCode` | `String` | 费用小类业务编码 (常用 `Expense(typeBizCode == "2001_01")` 判定住宿/打车费) |
| `amount` | `BigDecimal` | 费用收款币种实际金额 |
| `collectionCcy` / `baseCcy` | `String` | 收款币种 / 本币 |
| `consumeLocation` | `String` | 消费城市 (每刻标准地址编码) |
| `departure` / `destination` | `String` | 出发地 / 目的地 (每刻标准地址编码) |
| `consumeDate` | `DateTime` | 消费时间 |
| `startDate` / `endDate` | `DateTime` | 开始时间 / 结束时间 (常用于酒店入住退房区间) |
| `customFormValues` | `List<CustomFormValue>` | 费用行上的自定义字段 |
| `allowanceStandardInfos` | `List<AllowanceStandardInfo>` | 关联的补贴标准表集合 |
| `containBreakfast` | `int` | **是否含早字段**：`1`-含早餐；`2`-不含；`3`-未知/默认 |
| `expenseAllocations` | `List<ExpenseAllocation>` | 费用分摊明细列表 |
| `detailExecResultList` | `List<DistDetailExecResult>` | 对应的费控格子执行明细信息 |
| `expensePartnerStandardInfos` | `List<AllowanceStandardInfo>` | **费用参与人补贴信息** (官方 2026-06-24 新增) |
| `travelPartnerInfo` | `TravelPartnerInfo` | 参与人信息组 |

### 附：`ExpenseAllocation`（费用分摊信息）
- `code`: `String` - 分摊行唯一标识
- `expenseCode`: `String` - 费用行 `code`
- `coverUserCode` / `coverUserName`: `String` - 承担人编码与姓名
- `coverDepartmentCode` / `coverDepartmentName`: `String` - 承担部门编码与名称
- `legalEntityCode` / `legalEntityName`: `String` - 公司抬头编码与名称
- `allocatedAmount` / `allocatedRatio`: `BigDecimal` - 分摊金额 / 分摊比例
- `approvedBaseAmount` / `approvedAmount`: `BigDecimal` - 分摊本币金额 / 审批后金额
- `consumeCcy` / `baseCcy` / `collectionCcy`: `String` - 消费币种 / 本币 / 收款币种
- `customFormValues`: `List<CustomFormValue>` - 分摊明细自定义字段

---

## 4. 行程信息对象 (`TravelRoute`)

核心事实对象，绝大多数差旅补贴模板均以 `TravelRoute` 集合遍历展开。

| 参数名称 | 类型 | 描述与用途 |
| :--- | :--- | :--- |
| `travelRouteCode` | `String` | 行程 code（申请单明细配置为"需要挂在行程下显示"时，**必须把该 code 传入 `AllowanceResult.setTravelRouteCode(...)`**） |
| `startDate` / `endDate` | `DateTime` | 行程开始与结束时间 |
| `departure` / `destination` | `String` | 出发城市 / 目的城市 (每刻标准地址编码) |
| `departureText` / `destinationText` | `String` | 出发城市名称 / 目的城市名称 (文本字符串) |
| `tripWay` | `TripWay` | 行程类型枚举：`SINGLE` (单程) / `ROUND_TRIP` (往返) |
| `travelDays` | `BigDecimal` | 出差天数 |
| `allowanceStandardInfos` | `List<AllowanceStandardInfo>` | **报销人**匹配到的补贴标准池列表 |
| `partnerAllowanceStandardInfos` | `List<AllowanceStandardInfo>` | **参与人专属**补贴标准池列表 (优先级说明见下方要点) |
| `travelPartnerInfo` | `TravelPartnerInfo` | 行程参与人/同行人信息组 |
| `attendance` | `Attendance` | **考勤联动工时对象** (可结合实际工时发放补贴) |
| `customFormValues` | `List<CustomFormValue>` | 行程组件上的自定义选填字段 |
| `expenseCodeList` | `List<String>` | 行程关联的费用编码 (`code` 列表) |

> [!IMPORTANT]
> **官方参与人标准优先级说明**：
> 优先级为：**行程参与人标准信息 (`TravelRoute.partnerAllowanceStandardInfos`) > 单据参与人标准信息 (`Reimburse` 上的标准)**。
> 若行程中带有参与人信息，这里的标准即为行程参与人标准；若无，则为单据参与人标准；若单据和行程都无参与人，则为 `null`。因此在遍历同行人并调用 `allowanceService.getDestinationPartnerAllowanceStandard` 时，应优先使用 `$partnerAllowanceStandardInfos`。

### 附：`Attendance`（考勤信息对象）
- `startDate` / `endDate`: `DateTime` - 考勤统计开始/结束时间
- `calcDaysMode`: `CalcDaysMode` - 时长计算方式枚举：`NATURAL_DAY` (自然日) / `WORK_DAY` (工作日)
- `durationUnit`: `AttendanceDurationUnit` - 统计单元枚举：`DAY` (天) / `HALF_DAY` (半天) / `HOUR` (小时)
- `duration`: `double` - 实际考勤时长

---

## 5. 参与人信息组 (`TravelPartnerInfo`) 与参与人 (`TravelPartner`)

### 5.1 `TravelPartnerInfo` (参与人信息组)
| 参数名称 | 类型 | 描述 |
| :--- | :--- | :--- |
| `code` / `relationCode` | `String` | 参与人组编码 / 关联编码 |
| `internalTravelPartner` | `List<TravelPartner>` | **内部同行人列表** (最常循环遍历的对象) |
| `internalPeopleNum` | `BigDecimal` | 内部同行人总人数 |
| `internalReferenceFormCode` / `internalTravelPartnerTypeCode` | `String` | 内部同行人关联表单编码 / 小类编码 |
| `externalTravelPartner` | `List<TravelPartner>` | **外部同行人列表** |
| `externalPeopleNum` | `int` | 外部同行人总人数 |
| `externalReferenceFormCode` / `externalTravelPartnerTypeCode` | `BigDecimal` / `String` | 外部同行人表单编码 / 小类编码 |

### 5.2 `TravelPartner` (参与人详情)
| 参数名称 | 类型 | 描述 |
| :--- | :--- | :--- |
| `code` | `String` | 参与人行唯一编码 |
| `userCode` | `String` | **内部员工编码** (作为 `dateMap` 去重 key 或查询对应金额) |
| `name` / `employeeId` | `String` | 姓名 / 工号 |
| `externalUser` | `boolean` | 是否为外部人员 |
| `departmentCode` / `departmentBizCode` / `departmentName` | `String` | 部门编码 / 部门业务编码 / 部门名称 |
| `gender` | `String` | 性别：`MAN` / `WOMAN` |
| `peopleNum` | `int` | 参与人人数 |
| `classPosition` | `ClassPosition` | 职级对象 (`code`, `userGroupCode`, `name`, `businessCode`, `description`, `superiorCode`) *(注：官方说明该职级信息目前仅限返回单据级参与人组件，行程参与人暂未返回)* |
| `customObject` / `formDataCode` | `String` | 自定义对象 / 关联单据编码 |

---

## 6. 补贴标准与多目的地对象 (`AllowanceStandardInfo`)

### 6.1 `AllowanceStandardInfo` (补贴信息表)
- `sourceCode`: `String` - 资源编码（如果为费用补贴为费用编码，行程为行程编码）
- `hasDateDimension`: `boolean` - 是否开启按日期的日历标准维度
- `ruleName` / `ruleBizCode`: `String` - 补贴标准名称与业务编码
- `userCode`: `String` - 标准所属的人员内码
- `standardMap`: `Map<String, AllowanceStandard>` - 补贴标准 Map：
  - 当没有日期维度时：key 为 `ruleBizCode`。
  - 当有日期维度时：key 为 `ruleBizCode + "yyyy-MM-dd"`。
  - 当使用**国外/国内双套标准**或指定 `DESTINATION` 时：key 常为 `ruleBizCode + "DESTINATION"`，并通过 `((AllowanceStandard)standardMap.get(key)).getCurrency()` 动态获取目的地标准所属币种。
- `destinationStandards`: `List<DestinationAllowanceStandard>` - **行程多目的地补贴标准池** (官方 2026-06-25 新增支持)。

### 6.2 `DestinationAllowanceStandard` (行程多目的地标准明细)
- `destinationCode` / `destinationName`: `String` - 目的地城市编码与名称
- `ruleCellCode`: `String` - 规则格子编码
- `amount` / `currency`: `String` - 补贴金额与币种
- `consumeTime`: `String` - 消费时间
- `destIndex` / `total`: `int` - 当前目的地序号 / 目的地总数

---

## 7. 自定义表单与费控执行返回数据

### 7.1 `CustomFormValue` (选填字段内容)
- `bizCode`: `String` - **组件业务编码** (查找关键项，如 `allowanceService.getCustomFormValue($customFormValues, "CF186")`)
- `code` / `identifier` / `name`: `String` - 字段内码 / 占位符 / 组件名称
- `type`: `String` - 组件类型 (`SingleTextInput`, `MultiTextInput`, `NumberInput`, `OptionInput`)
- `value`: `String` - 填写的文本内容或选项内码 (`SubOptionCode`)

### 7.2 `ExpenseStandResult` / `DistDetailExecResult` (费控格子结果)
- `ExpenseStandResult`:
  - `key`: `String` - 部门业务编码
  - `finalStdOriginAmt` / `finalStdActualAmt`: `MonetaryAmount` - 原始上限金额 / 调整后最终上限金额 (`MonetaryAmount.amount` 为 `BigDecimal`，`currency` 为 `String`)
- `DistDetailExecResult`:
  - `expenseCode` / `expenseTypeCode`: `String` - 费用内码 / 类型编码
  - `dateType`: `String` - 周期：`TIME`, `YEAR`, `QUARTER`, `MONTH`, `DAY`
  - `effectiveDate`: `Integer` - 生效日期 `yyyyMMdd`
  - `amountUsage`: `UserAmtVaryUsage` (`finalUserCode`, `finalStdActualAmt`, `execAmt`)
