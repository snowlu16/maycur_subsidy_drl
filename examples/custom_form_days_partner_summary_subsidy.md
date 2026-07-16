# 表单自定义天数 + 同行人合并整单汇总计算补贴 (Custom Form Days & Travel Partners Summary)

> **场景适用**：
> 1. 补贴天数不通过单据行程计算，而是直接从报销单/申请单表头自定义字段（业务编码：`CF105`）输入；
> 2. 报销单/申请单上包含同行人（参与人）；
> 3. 补贴标准为 **每天/每人 50 元**；
> 4. 无论出差多少天、有多少同行参与人，最终全单**合并生成一笔费用明细 (`AllowanceResult`)**，费用类型编码为 `32`。

---

```drools
package rules;

import java.util.*;
import java.math.BigDecimal;
import org.joda.time.DateTime;
import org.slf4j.Logger;

import com.maycur.sdk.rule.domain.*;
import com.maycur.sdk.rule.domain.result.*;
import com.maycur.sdk.rule.service.*;

global AllowanceService allowanceService;
global Logger logger;

dialect "mvel"

// ==========================================
// 1. 声明全局参数结构体
// ==========================================
declare CustomDaysPartnersParams
    customFieldBizCode : String  // 单表头“天数”自定义字段编码 (CF105)
    feeCode : String             // 生成的整单补贴费用类型编码 (32)
    dailyRatePerPerson : BigDecimal // 每天每人补贴金额 (50元)
end

// ==========================================
// 2. 初始化基础参数 (Salience 30)
// ==========================================
rule "初始化表单自定义天数与参与人参数"
    salience 30
    when
        Reimburse()
    then
        String customFieldBizCode = "CF105"; // 自定义天数字段编码
        String feeCode = "32";               // 生成的报销明细费用编码
        BigDecimal dailyRatePerPerson = new BigDecimal("50"); // 每天/每人 50 元

        insert(new CustomDaysPartnersParams(customFieldBizCode, feeCode, dailyRatePerPerson));
        logger.info("初始化完成: customFieldBizCode={}, feeCode={}, 每天每人标准={}", customFieldBizCode, feeCode, dailyRatePerPerson);
end

// ==========================================
// 3. 计算并汇总整单一笔补贴 (Salience 20)
// ==========================================
rule "根据表单自定义天数及同行人数汇总计算整单补贴"
    salience 20
    when
        CustomDaysPartnersParams(
            $customFieldBizCode : customFieldBizCode,
            $feeCode : feeCode,
            $dailyRatePerPerson : dailyRatePerPerson
        );
        $reimburse : Reimburse(
            $customFormValues : customFormValues,
            $travelRoutes : travelRoutes,
            $travelPartnerInfo : travelPartnerInfo,
            $baseCcy : baseCcy,
            $collectionCcy : collectionCcy,
            $submittedAt : submittedAt
        );
    then
        // ----------------------------------------------------
        // 步骤 1：读取单据表头自定义“天数”字段 (CF105)
        // ----------------------------------------------------
        String daysStr = allowanceService.getCustomFormValue($customFormValues, $customFieldBizCode);
        logger.info("读取到自定义字段 [{}] 的填报天数内容为: {}", $customFieldBizCode, daysStr);

        if (daysStr == null || daysStr.trim().isEmpty()) {
            logger.warn("未读取到天数字段值 [{}]，跳过补贴计算", $customFieldBizCode);
            return;
        }

        BigDecimal days = BigDecimal.ZERO;
        try {
            days = new BigDecimal(daysStr.trim());
        } catch (Exception e) {
            logger.error("天数字段内容 [{}] 无法解析为数值，跳过补贴计算", daysStr);
            return;
        }

        if (days.compareTo(BigDecimal.ZERO) <= 0) {
            logger.info("填报天数 {} 小于等于 0，不生成补贴", days);
            return;
        }

        // ----------------------------------------------------
        // 步骤 2：统计本次出差总人数 (报销人自身 + 同行参与人)
        // ----------------------------------------------------
        long personCount = 1; // 默认包含报销人自己 (1 人)

        // 获取参与人信息对象（优先自单据头部获取，若头部无则自首段行程获取）
        TravelPartnerInfo partnerInfo = $travelPartnerInfo;
        if (partnerInfo == null && $travelRoutes != null && !$travelRoutes.isEmpty()) {
            partnerInfo = ((TravelRoute) $travelRoutes.get(0)).getTravelPartnerInfo();
        }

        if (partnerInfo != null) {
            // 统计内部同行人数量
            if (partnerInfo.getInternalTravelPartner != null) {
                personCount += partnerInfo.getInternalTravelPartner.size();
                logger.info("统计到内部同行参与人 {} 人", partnerInfo.getInternalTravelPartner.size());
            }
            // 统计外部同行人数量
            if (partnerInfo.getExternalTravelPartner != null) {
                personCount += partnerInfo.getExternalTravelPartner.size();
                logger.info("统计到外部同行参与人 {} 人", partnerInfo.getExternalTravelPartner.size());
            }
        }
        logger.info("本次出差合计计算人数(报销人+同行人)为: {} 人", personCount);

        // ----------------------------------------------------
        // 步骤 3：计算最终整单补贴总金额 = 天数 * 总人数 * 单人单日标准 (50元)
        // ----------------------------------------------------
        BigDecimal totalPeople = new BigDecimal(personCount);
        BigDecimal totalAmount = days.multiply(totalPeople).multiply($dailyRatePerPerson).setScale(2, BigDecimal.ROUND_HALF_UP);
        logger.info("计算总补贴: {}天 * {}人 * {}元/天/人 = {}", days, totalPeople, $dailyRatePerPerson, totalAmount);

        // ----------------------------------------------------
        // 步骤 4：确定时间区间与行程挂靠
        // ----------------------------------------------------
        DateTime startDate = ($submittedAt != null) ? $submittedAt : DateTime.now();
        DateTime endDate = startDate;
        String travelRouteCode = null;
        String consumeLocation = null;

        if ($travelRoutes != null && !$travelRoutes.isEmpty()) {
            TravelRoute firstRoute = (TravelRoute) $travelRoutes.get(0);
            TravelRoute lastRoute = (TravelRoute) $travelRoutes.get($travelRoutes.size() - 1);
            if (firstRoute.getStartDate() != null) {
                startDate = firstRoute.getStartDate();
            }
            if (lastRoute.getEndDate() != null) {
                endDate = lastRoute.getEndDate();
            }
            travelRouteCode = firstRoute.getTravelRouteCode();
            consumeLocation = firstRoute.getDestination();
        }

        // ----------------------------------------------------
        // 步骤 5：构造整单唯一的 AllowanceResult 并插入内存
        // ----------------------------------------------------
        if (totalAmount.compareTo(BigDecimal.ZERO) > 0) {
            AllowanceResult result = new AllowanceResult(
                startDate,
                endDate,
                $feeCode,
                totalAmount,
                $baseCcy,
                $collectionCcy
            );

            // 若申请单/报销单带有行程，必须挂靠行程 Code 否则前端明细行不渲染显示
            if (travelRouteCode != null && !travelRouteCode.isEmpty()) {
                result.setTravelRouteCode(travelRouteCode);
            }
            if (consumeLocation != null && !consumeLocation.isEmpty()) {
                result.setConsumeLocation(consumeLocation);
            }

            insert(result);
            logger.info("🎉 成功插入整笔合并补贴: 费用编码={}, 合计金额={}, 挂靠行程={}", $feeCode, totalAmount, travelRouteCode);
        }
end
```
