# template_2_7_option_deduction

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
// 模板 2.7：含行程同行人 + 含报销人，按行程汇总
// 核心特性：行程上的自定义选项字段触发扣减
//           若行程内存在某个自定义选项字段被勾选（如"是否提供三餐" = YES），
//           则该行程所有人补贴按 deductionRate 扣减对应比例
//
// 参数说明：
//   bizCode           - 补贴标准业务编码
//   feeCode           - 生成补贴费用的费用类型编码
//   optionFieldBizCode - 行程自定义字段的 bizCode（如 "CF_MEAL"）
//   triggerOptionValue - 触发扣减的选项值/内码（如 "YES" 或 "true"）
//   deductionRate     - 扣减比例（如 0.5 = 扣 50%，给 50%；1.0 = 全扣为0）
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

rule "按行程汇总_行程选项扣减"
    salience 20
    when
        GlobalParams($dateMap: dateMap, $bizCode: bizCode)
        Reimburse(
            $travelRoutes: travelRoutes,
            $reimEmployee: reimEmployee,
            $baseCcy: baseCcy
        )
        eval($reimEmployee != null)
        $travelRoute : TravelRoute(
            $startDate: startDate,
            $endDate: endDate,
            $destination: destination,
            $allowanceStandardInfos: allowanceStandardInfos,
            $travelPartnerInfo: travelPartnerInfo,
            $routeFormValues: customFormValues
        ) from $travelRoutes
        $allowanceStandardInfo: AllowanceStandardInfo(
            $bizCode.equals(ruleBizCode)
        ) from $allowanceStandardInfos
    then
        // ===== 可调参数 =====
        String optionFieldBizCode = "CF_MEAL";         // TODO: 行程自定义字段 bizCode
        String triggerOptionValue = "YES";             // TODO: 触发扣减的选项内码
        BigDecimal deductionRate = new BigDecimal("0.5");  // 扣 50%
        // ====================

        // 检查该行程是否触发扣减条件
        boolean shouldDeduct = false;
        if ($routeFormValues != null) {
            for (Object cfvObj : $routeFormValues) {
                CustomFormValue cfv = (CustomFormValue) cfvObj;
                if (optionFieldBizCode.equals(cfv.getBizCode()) && triggerOptionValue.equals(cfv.getValue())) {
                    shouldDeduct = true;
                    break;
                }
            }
        }
        logger.info("行程 {} 是否触发选项扣减: {}", $destination, shouldDeduct);

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

            // 按选项扣减
            if (shouldDeduct) {
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

                    if (shouldDeduct) {
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
