# template_2_11_expense_diff_subsidy

```drools
package rules;

import java.util.*;
import java.math.BigDecimal;
import java.math.RoundingMode;
import com.maycur.sdk.rule.domain.*;
import com.maycur.sdk.rule.domain.result.*;
import com.maycur.sdk.rule.service.*;
import org.joda.time.DateTime;
import org.slf4j.Logger;

global AllowanceService allowanceService;
global Logger logger;

dialect "mvel"

// ==========================================
// 模板 2.11：含报销人，按行程汇总
// 核心特性：匹配费用按照差额比例做补贴（节约差额返还）
//
// 业务逻辑（来自官方 usg5m5 说明）：
//   若存在指定类型的费用（如住宿费），则按消费日期天数（结束日期不计）计算：
//     日均费用 = 费用金额 / (天数 - 1)
//   对每天判断：
//     差额 = 补贴标准 - 日均费用
//     若差额 > 0（未超标，节约了），则按 (差额 × deductionRate) 返还
//     若差额 <= 0（超标），则返回 0
//   其他未被关联费用覆盖的天，按正常补贴标准全额返还
//
// 案例（来自官方说明）：
//   补贴标准：每天200元，报销住宿3晚（1.1-1.4），住宿费实际报销600元
//   日均费用 = 600 / 3 = 200
//   差额 = 200 - 200 = 0，不返还差额补贴
//   若报销500元：日均 500/3 ≈ 167，差额 200-167=33，返还 33 × 0.5 ≈ 16.5
//
// 参数说明：
//   bizCode        - 补贴标准业务编码
//   feeCode        - 生成补贴费用的费用类型编码
//   targetFeeType  - 要匹配的费用类型编码（如住宿费 "2001_01"）
//   deductionRate  - 差额返还比例（如 0.5 = 返还差额的 50%）
// ==========================================

declare GlobalParams
    dateMap : Map
    bizCode : String
end

rule "初始化参数"
    salience 30
    when
        Reimburse()
    then
        insert(new GlobalParams(new HashMap(), "YOUR_BIZ_CODE"));
end

rule "按行程汇总_差额比例补贴"
    salience 20
    when
        GlobalParams($dateMap: dateMap, $bizCode: bizCode)
        Reimburse(
            $travelRoutes: travelRoutes,
            $expenses: expenses,
            $reimEmployee: reimEmployee,
            $baseCcy: baseCcy
        )
        eval($reimEmployee != null)
        $travelRoute : TravelRoute(
            $startDate: startDate,
            $endDate: endDate,
            $destination: destination,
            $allowanceStandardInfos: allowanceStandardInfos
        ) from $travelRoutes
        $allowanceStandardInfo: AllowanceStandardInfo(
            $bizCode.equals(ruleBizCode)
        ) from $allowanceStandardInfos
    then
        // ===== 可调参数 =====
        String targetFeeType = "2001_01";              // TODO: 替换为要匹配的费用类型编码（住宿费等）
        BigDecimal deductionRate = new BigDecimal("0.5");  // 差额返还比例
        // ====================

        // 找到与该行程关联的目标类型费用
        // 逻辑：费用的消费日期区间与行程区间有交叉，取该费用
        Expense matchedExpense = null;
        for (Object expObj : $expenses) {
            Expense exp = (Expense) expObj;
            if (!targetFeeType.equals(exp.getTypeBizCode())) continue;
            if (exp.getStartDate() == null || exp.getEndDate() == null) continue;
            // 简单判断：费用开始日期在行程区间内
            DateTime expStart = new DateTime(exp.getStartDate().getYear(), exp.getStartDate().getMonthOfYear(),
                exp.getStartDate().getDayOfMonth(), 0, 0, 0);
            DateTime routeStart = new DateTime($startDate.getYear(), $startDate.getMonthOfYear(), $startDate.getDayOfMonth(), 0, 0, 0);
            DateTime routeEnd = new DateTime($endDate.getYear(), $endDate.getMonthOfYear(), $endDate.getDayOfMonth(), 0, 0, 0);
            if (!expStart.isBefore(routeStart) && !expStart.isAfter(routeEnd)) {
                matchedExpense = exp;
                break;
            }
        }

        BigDecimal totalAmount = BigDecimal.ZERO;
        String currency = $baseCcy;
        List dateTimes = allowanceService.getTripDiffDays($travelRoute);

        // 计算日均费用（若有关联费用）
        BigDecimal dailyExpenseAvg = null;
        if (matchedExpense != null && matchedExpense.getAmount() != null) {
            // 天数 = 费用天数 - 1（结束日不计，如住宿 1.1-1.4 共3晚=3天）
            List expDays = matchedExpense.days();
            int expDayCount = (expDays != null && expDays.size() > 1) ? expDays.size() - 1 : 1;
            dailyExpenseAvg = matchedExpense.getAmount().divide(new BigDecimal(expDayCount), 2, RoundingMode.HALF_UP);
            logger.info("匹配到费用: amount={}, 日均费用={}", matchedExpense.getAmount(), dailyExpenseAvg);
        }

        for (Object dt : dateTimes) {
            DateTime consumeTime = (DateTime) dt;
            int status = allowanceService.isDayHalveOrOverlap($dateMap, $reimEmployee.getUserCode(), consumeTime, $startDate, $endDate);
            if (status == -1) continue;

            BigDecimal stdRate = allowanceService.getDestinationAllowanceStandard(consumeTime, $allowanceStandardInfo);
            if (stdRate == null || stdRate.compareTo(BigDecimal.ZERO) <= 0) continue;

            if (currency == null || currency.equals($baseCcy)) {
                currency = allowanceService.getDestinationAllowanceStandardCcy(consumeTime, $allowanceStandardInfo);
            }

            BigDecimal dayAmount;
            if (dailyExpenseAvg != null) {
                // 差额补贴：(标准 - 日均费用) × 返还比例
                BigDecimal diff = stdRate.subtract(dailyExpenseAvg);
                if (diff.compareTo(BigDecimal.ZERO) > 0) {
                    dayAmount = diff.multiply(deductionRate).setScale(2, RoundingMode.HALF_UP);
                } else {
                    // 超标不发补贴
                    dayAmount = BigDecimal.ZERO;
                }
            } else {
                // 无关联费用：按正常标准全额发放
                dayAmount = stdRate;
            }

            totalAmount = totalAmount.add(dayAmount);
        }

        if (totalAmount.compareTo(BigDecimal.ZERO) > 0) {
            AllowanceResult result = new AllowanceResult($startDate, $endDate, "YOUR_FEE_CODE", totalAmount, $baseCcy, currency, $destination);
            result.setTravelRouteCode($travelRoute.getTravelRouteCode());
            insert(result);
        }
end
```
