# 每刻补贴脚本 (Maycur DRL) 开发者零基础极简快速上手指南 (Quick Start Guide)

> 本文档专为初次接触或刚上手每刻报销 Drools 规则脚本的开发者打造。摒弃晦涩复杂的长篇逻辑，从最基础的**运行机制**、**极简复制即用模板**到**常见踩坑排查**，助你在 5 分钟内完成第一条合法运行的补贴脚本！

---

## 一、 核心概念与工作机制：一分钟读懂

每刻报销补贴计算的核心本质：**系统输入单据与行程 -> Drools 引擎执行脚本计算 -> 脚本 `insert` 输出结果。**

### 1. 系统自动注入了哪些输入对象（输入 `when`）？
当你开启了脚本计算并提交报销单时，系统会在引擎工作内存中自动就绪以下对象：
- `Reimburse`：报销单或出差申请单主表信息。
- `TravelRoute` (`$travelRoutes`)：行程列表，每条行程包含 `$startDate`（出发时间）、`$endDate`（到达时间）、`$destination`（目的地编码字符串，如 `330000-330100-330106`）、`$allowanceStandardInfos`（报销人标准金额列表）、`$partnerAllowanceStandardInfos`（参与人标准金额列表）。
- `Expense` (`$expenses`)：单单中已录入的其他费用明细（常用于判断有没有打车费/餐饮费来做扣减）。
- `ReimEmployee` (`$reimEmployee`)：员工与常驻地信息。

### 2. 脚本如何把计算结果给系统（输出 `then` -> `insert`）？
你只需在 Java/Mvel 代码段中计算出金额 `BigDecimal amount`，随后创建并配置一个 `AllowanceResult` 对象，通过调用 **`insert(result)`** 放入内存。规则执行完成后，系统会自动收集所有被 `insert` 的 `AllowanceResult`，并在前端自动生成明细报销行！

---

## 二、 开箱即用：两大基础通用极简模板骨架 (Copy & Paste Skeleton)

刚开始写脚本不要从零拼写 `declare` 和复杂规则，请直接根据业务场景复制以下两个标准极简骨架之一，修改 **`bizCode`** 和 **`feeCode`** 即可直接跑通！

### 骨架 A：全天通用极简模板（按行程区间计算报销人+参与人）
> **适用场景**：不论几点出发返回，按天数累加去重（同一天多条行程不重复计算补贴）。

```drools
package com.maycur.drl;

import com.maycur.entity.Reimburse;
import com.maycur.entity.TravelRoute;
import com.maycur.entity.TravelPartner;
import com.maycur.entity.AllowanceStandardInfo;
import com.maycur.entity.AllowanceResult;
import com.maycur.util.DateTime;
import java.math.BigDecimal;
import java.util.Map;
import java.util.HashMap;
import java.util.List;
import java.util.ArrayList;

// ======================= 1. 声明全局容器 =======================
declare TravelHalfDayKeys
    dateMap : Map
    bizCode : String
    feeCode : String
end

// ======================= 2. 初始化核心参数 (TODO: 修改此处) =======================
rule "初始化核心参数"
    salience 30
    when Reimburse();
    then
        // TODO: 请修改为每刻后台补贴标准对应的 businessCode
        String bizCode = "travelAllowanceStandard";
        // TODO: 请修改为生成补贴对应的费用类型编码 (如：BT、SUB_01)
        String feeCode = "BT";
        insert(new TravelHalfDayKeys(new HashMap(), bizCode, feeCode));
end

// ======================= 3. 日期去重函数 =======================
function boolean isDayOverlap(Map map, String userCode, DateTime dateTime) {
    List days = (map.get(userCode) == null) ? new ArrayList() : (List)map.get(userCode);
    String day = dateTime.toString("yyyy-MM-dd");
    if (!days.contains(day)) {
        days.add(day);
        map.put(userCode, days);
        return false; // 未重叠，允许计算
    }
    return true; // 重叠，跳过
}

// ======================= 4. 核心计算规则 =======================
rule "计算报销人与参与人全天补贴"
    salience 20
    when
        $travelHalfDayKeys : TravelHalfDayKeys($dateMap : dateMap, $bizCode : bizCode, $feeCode : feeCode);
        $reimburse : Reimburse($companyCode : companyCode);
        $travelRecord : TravelRoute(
            $startDate : startDate,
            $endDate : endDate,
            $destination : destination,
            $travelRouteCode : travelRouteCode,
            $allowanceStandardInfos : allowanceStandardInfos,
            $partnerAllowanceStandardInfos : partnerAllowanceStandardInfos,
            $travelPartnerInfo : travelPartnerInfo
        ) from $reimburse.getTravelRoutes;
    then
        BigDecimal amount = new BigDecimal("0");
        String currency = "CNY";

        // 遍历行程区间每一天
        DateTime dateTime = $startDate;
        while (dateTime.compareTo($endDate) <= 0) {
            // ---- 1. 计算报销人本人补贴 ----
            BigDecimal myAmount = allowanceService.getDestinationAllowanceStandard(dateTime, $allowanceStandardInfos, $bizCode);
            if (!isDayOverlap($dateMap, $reimburse.getUserCode(), dateTime)) {
                amount = amount.add(myAmount);
                if (allowanceService.getDestinationAllowanceStandardCcy(dateTime, $allowanceStandardInfos) != null) {
                    currency = allowanceService.getDestinationAllowanceStandardCcy(dateTime, $allowanceStandardInfos);
                }
            }

            // ---- 2. 计算同行参与人补贴 ----
            if ($travelPartnerInfo != null && $travelPartnerInfo.getInternalTravelPartner != null) {
                for (TravelPartner partner : $travelPartnerInfo.getInternalTravelPartner) {
                    BigDecimal partnerAmount = allowanceService.getDestinationPartnerAllowanceStandard(dateTime, $partnerAllowanceStandardInfos, partner, $bizCode);
                    if (!isDayOverlap($dateMap, partner.getUserCode(), dateTime)) {
                        amount = amount.add(partnerAmount);
                    }
                }
            }
            dateTime = dateTime.plusDays(1);
        }

        // ---- 3. 如果总金额大于 0，则插入系统内存输出结果 ----
        if (amount.compareTo(BigDecimal.ZERO) == 1) {
            AllowanceResult result = new AllowanceResult($startDate, $endDate, $feeCode, amount, currency, currency);
            result.setTravelRouteCode($travelRouteCode); // 关键！必填挂靠行程
            result.setConsumeLocation($destination);
            insert(result);
        }
end
```

---

### 骨架 B：半天通用极简模板（12:00 分界：上午/下午独立核算）
> **适用场景**：中午 12:00 以后出发计半天（减半），中午 12:00 以前到达返回计半天（减半）。

```drools
package com.maycur.drl;

import com.maycur.entity.Reimburse;
import com.maycur.entity.TravelRoute;
import com.maycur.entity.TravelPartner;
import com.maycur.entity.AllowanceStandardInfo;
import com.maycur.entity.AllowanceResult;
import com.maycur.util.DateTime;
import java.math.BigDecimal;
import java.util.Map;
import java.util.HashMap;
import java.util.List;
import java.util.ArrayList;

declare TravelHalfDayKeys
    dateMap : Map
    bizCode : String
    feeCode : String
end

rule "初始化半天参数"
    salience 30
    when Reimburse();
    then
        String bizCode = "travelAllowanceStandard"; // TODO: 修改后台配置的标准编码
        String feeCode = "BT";                      // TODO: 修改生成的费用类型编码
        insert(new TravelHalfDayKeys(new HashMap(), bizCode, feeCode));
end

// 返回值说明: -1=重叠跳过; 0=算半天(金额折半); 1=全天(正常金额)
function int isDayHalveOrOverlap(Map map, String userCode, DateTime day, DateTime startDate, DateTime endDate) {
    int flag = 1;
    List days = (map.get(userCode) == null) ? new ArrayList() : (List)map.get(userCode);
    String amDay = day.toString("yyyy-MM-dd") + "am";
    String pmDay = day.toString("yyyy-MM-dd") + "pm";
    
    // 出发当天且大于等于 12:00，算下午半天
    if (day.getYear()==startDate.getYear() && day.getMonthOfYear()==startDate.getMonthOfYear() && day.getDayOfMonth()==startDate.getDayOfMonth()) {
        if (startDate.getHourOfDay() >= 12) {
            if (days.contains(pmDay)) return -1;
            days.add(pmDay); map.put(userCode, days); return 0;
        }
    }
    // 返回当天且小于等于 12:00，算上午半天
    if (day.getYear()==endDate.getYear() && day.getMonthOfYear()==endDate.getMonthOfYear() && day.getDayOfMonth()==endDate.getDayOfMonth()) {
        if (endDate.getHourOfDay() < 12 || (endDate.getHourOfDay() == 12 && endDate.getMinuteOfHour() == 0)) {
            if (days.contains(amDay)) return -1;
            days.add(amDay); map.put(userCode, days); return 0;
        }
    }
    // 中间日期或早去晚回：判断上下午是否都被占过
    if (days.contains(amDay) && days.contains(pmDay)) return -1;
    if (days.contains(amDay)) flag = 0; else days.add(amDay);
    if (days.contains(pmDay)) flag = 0; else days.add(pmDay);
    map.put(userCode, days);
    return flag;
}

rule "计算半天行程补贴"
    salience 20
    when
        $travelHalfDayKeys : TravelHalfDayKeys($dateMap : dateMap, $bizCode : bizCode, $feeCode : feeCode);
        $reimburse : Reimburse();
        $travelRecord : TravelRoute(
            $startDate : startDate, $endDate : endDate, $destination : destination,
            $travelRouteCode : travelRouteCode, $allowanceStandardInfos : allowanceStandardInfos
        ) from $reimburse.getTravelRoutes;
    then
        BigDecimal amount = new BigDecimal("0");
        String currency = "CNY";
        DateTime dateTime = $startDate;
        while (dateTime.compareTo($endDate) <= 0) {
            BigDecimal myAmount = allowanceService.getDestinationAllowanceStandard(dateTime, $allowanceStandardInfos, $bizCode);
            int status = isDayHalveOrOverlap($dateMap, $reimburse.getUserCode(), dateTime, $startDate, $endDate);
            if (status == 1) {
                amount = amount.add(myAmount); // 全天
            } else if (status == 0) {
                amount = amount.add(myAmount.multiply(new BigDecimal("0.5"))); // 半天折半
            }
            dateTime = dateTime.plusDays(1);
        }
        if (amount.compareTo(BigDecimal.ZERO) == 1) {
            AllowanceResult result = new AllowanceResult($startDate, $endDate, $feeCode, amount, currency, currency);
            result.setTravelRouteCode($travelRouteCode);
            result.setConsumeLocation($destination);
            insert(result);
        }
end
```

---

## 三、 开发者常见必踩大坑与排错字典 (Troubleshooting FAQ)

### Q1: 为什么脚本没有报错，但在单单里就算出来的金额永远是 0 / 取不到标准金额？
* **原因 A（最常踩坑）**：每刻管理后台配置“补贴标准”的时候，**行/列维度必须至少选择【城市】维度**！如果你选了无维度，或者没选城市，`getDestinationAllowanceStandard` 系统接口会无法匹配 `destination`，直接返回 `BigDecimal.ZERO`。即便全公司统一定额，也要选“全部城市”。
* **原因 B**：行程上的 `destination` 为空或者不是标准行政区划编码。
* **原因 C**：在调用 `allowanceService` 时，传入的 `$bizCode` 和你管理后台建补贴标准时写的业务编码拼写不一致。

### Q2: 为什么日志里能看到 `amount > 0` 且代码也运行了，但单据页面依然不显示报销明细行？
* **原因 A**：你新建 `AllowanceResult` 后，**忘记调用 `result.setTravelRouteCode($travelRouteCode)`**。差旅申请单或关联单据强依赖行程 Code 来挂靠并渲染明细行。
* **原因 B**：当你当次计算的 `amount` 为 0 时，千万不要调用 `insert(result)`。如果在金额为 0 时也强行 `insert`，可能会导致前端渲染异常或系统校验报错。请始终使用 `if (amount.compareTo(BigDecimal.ZERO) == 1) { insert(result); }` 保护。

### Q3: 参与人（同行人）明明配置了标准，为什么算不出来钱？
* **原因**：请检查你传给 `getDestinationPartnerAllowanceStandard` 的标准列表变量名！
  - **错误写法**：把报销人的 `$allowanceStandardInfos` 传给了参与人；
  - **正确写法**：在 `TravelRoute` 模式解构时提取 `$partnerAllowanceStandardInfos : partnerAllowanceStandardInfos`，传给参与人调用！

### Q4: Mvel / Java 片段报 `NullPointerException` 或日期解析方法不存在？
* **原因**：每刻 Drools 引擎内部对日期对象使用的是 **Joda-Time** (`com.maycur.util.DateTime` / `org.joda.time.DateTime`)。千万不要用 Java 8 的 `LocalDate` / `LocalDateTime` 方法！
* **常用操作速记**：
  - 加一天：`dateTime.plusDays(1)`
  - 比对大小：`dateTime.compareTo($endDate) <= 0`
  - 转日期字符串：`dateTime.toString("yyyy-MM-dd")`
  - 取小时：`dateTime.getHourOfDay()`

---

## 四、 进阶学习：全场景真实脚本传送门

熟悉了基本骨架后，当你有更复杂的需求（例如扣减早餐、打车费对半、多套国内外标准路由、常驻地清零等），可随时查看技能库中 `examples/` 目录下的 **45 个全量实操案例**：
- [查看完整 45 种真实场景代码索引](file:///references/usg5m5_templates.md)
