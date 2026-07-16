# template_2_4_expense_date_deduction

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
// 模板 2.4 / 1.2 / 1.7：含行程同行人 + 含报销人，按行程汇总
// 核心特性：若单据内存在指定类型的费用（如招待费/交通费），
//           且该费用的消费日期在行程范围内，则对行程对应日期的补贴按 deductionRate 扣减
//
// 参数说明：
//   bizCode          - 补贴标准业务编码
//   feeCode          - 生成补贴费用的费用类型编码
//   targetFeeType    - 触发扣减的费用类型编码（如 "020.001" 餐饮费）
//   deductionRate    - 扣减比例（如 0.5 = 扣除 50%，即只给 50%；1.0 = 全扣不给）
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

rule "按行程汇总_有指定费用则日期扣减"
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
            $allowanceStandardInfos: allowanceStandardInfos,
            $travelPartnerInfo: travelPartnerInfo
        ) from $travelRoutes
        $allowanceStandardInfo: AllowanceStandardInfo(
            $bizCode.equals(ruleBizCode)
        ) from $allowanceStandardInfos
    then
        // ===== 可调参数 =====
        String targetFeeType = "020.001";              // TODO: 替换为触发扣减的费用类型编码
        BigDecimal deductionRate = new BigDecimal("0.5");  // 扣减 50%，即只给一半
        // ====================

        // 收集触发扣减的日期集合（消费日期在行程区间内）
        Set deductDates = new HashSet();
        for (Object expObj : $expenses) {
            Expense exp = (Expense) expObj;
            if (!targetFeeType.equals(exp.getTypeBizCode())) continue;
            if (exp.getConsumeDate() == null) continue;
            DateTime consumeDate = new DateTime(exp.getConsumeDate().getYear(),
                exp.getConsumeDate().getMonthOfYear(), exp.getConsumeDate().getDayOfMonth(), 0, 0, 0);
            // 判断该消费日期是否在行程范围内
            DateTime routeStart = new DateTime($startDate.getYear(), $startDate.getMonthOfYear(), $startDate.getDayOfMonth(), 0, 0, 0);
            DateTime routeEnd = new DateTime($endDate.getYear(), $endDate.getMonthOfYear(), $endDate.getDayOfMonth(), 0, 0, 0);
            if (!consumeDate.isBefore(routeStart) && !consumeDate.isAfter(routeEnd)) {
                deductDates.add(consumeDate);
            }
        }
        logger.info("行程 {} 范围内触发扣减的日期数: {}", $destination, deductDates.size());

        BigDecimal totalAmount = BigDecimal.ZERO;
        String currency = $baseCcy;
        List dateTimes = allowanceService.getTripDiffDays($travelRoute);

        // 报销人
        for (Object dt : dateTimes) {
            DateTime consumeTime = (DateTime) dt;
            int status = allowanceService.isDayHalveOrOverlap($dateMap, $reimEmployee.getUserCode(), consumeTime, $startDate, $endDate);
            if (status == -1) continue;

            BigDecimal dailyRate = allowanceService.getDestinationAllowanceStandard(consumeTime, $allowanceStandardInfo);
            if (dailyRate == null || dailyRate.compareTo(BigDecimal.ZERO) <= 0) continue;

            if (currency == null || currency.equals($baseCcy)) {
                currency = allowanceService.getDestinationAllowanceStandardCcy(consumeTime, $allowanceStandardInfo);
            }

            // 若该日期在扣减集合中，按比例扣减
            DateTime day0 = new DateTime(consumeTime.getYear(), consumeTime.getMonthOfYear(), consumeTime.getDayOfMonth(), 0, 0, 0);
            if (deductDates.contains(day0)) {
                dailyRate = dailyRate.multiply(BigDecimal.ONE.subtract(deductionRate)).setScale(2, RoundingMode.HALF_UP);
            }

            totalAmount = totalAmount.add(dailyRate);
        }

        // 行程参与人
        if ($travelPartnerInfo != null && $travelPartnerInfo.getInternalTravelPartner() != null) {
            for (Object partnerObj : $travelPartnerInfo.getInternalTravelPartner()) {
                TravelPartner partner = (TravelPartner) partnerObj;
                if (partner == null || partner.getUserCode() == null) continue;

                for (Object dt : dateTimes) {
                    DateTime consumeTime = (DateTime) dt;
                    int status = allowanceService.isDayHalveOrOverlap($dateMap, partner.getUserCode(), consumeTime, $startDate, $endDate);
                    if (status == -1) continue;

                    BigDecimal dailyRate = allowanceService.getDestinationPartnerAllowanceStandard(
                        consumeTime, $allowanceStandardInfos, partner, $bizCode
                    );
                    if (dailyRate == null || dailyRate.compareTo(BigDecimal.ZERO) <= 0) continue;

                    DateTime day0 = new DateTime(consumeTime.getYear(), consumeTime.getMonthOfYear(), consumeTime.getDayOfMonth(), 0, 0, 0);
                    if (deductDates.contains(day0)) {
                        dailyRate = dailyRate.multiply(BigDecimal.ONE.subtract(deductionRate)).setScale(2, RoundingMode.HALF_UP);
                    }

                    totalAmount = totalAmount.add(dailyRate);
                }
            }
        }

        if (totalAmount.compareTo(BigDecimal.ZERO) > 0) {
            AllowanceResult result = new AllowanceResult($startDate, $endDate, "YOUR_FEE_CODE", totalAmount, $baseCcy, currency, $destination);
            result.setTravelRouteCode($travelRoute.getTravelRouteCode());
            insert(result);
        }
end
```
