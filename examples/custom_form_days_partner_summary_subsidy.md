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

dialect "java"

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
            $travelPartnerInfo : travelPartnerInfo,
            $baseCcy : baseCcy,
            $collectionCcy : collectionCcy,
            $submittedAt : submittedAt
        );
    then
        try {
            // ----------------------------------------------------
            // 步骤 1：读取单据表头自定义“天数”字段 (CF105)
            // ----------------------------------------------------
            if ($customFormValues == null) {
                logger.warn("未读取到单据表头自定义字段集合 ($customFormValues 为 null)，跳过补贴计算");
                return;
            }
            String daysStr = allowanceService.getCustomFormValue($customFormValues, $customFieldBizCode);
            logger.info("读取到报销单自定义天数字段 [{}] 的内容为: {}", $customFieldBizCode, daysStr);

            if (daysStr == null || daysStr.trim().isEmpty()) {
                logger.warn("未读取到天数字段值 [{}] 或填报为空，跳过本次补贴生成", $customFieldBizCode);
                return;
            }

            BigDecimal days = BigDecimal.ZERO;
            try {
                days = new BigDecimal(daysStr.trim());
            } catch (Exception e) {
                logger.error("天数字段内容 [{}] 无法转换/解析为有效数值，跳过计算", daysStr);
                return;
            }

            if (days.compareTo(BigDecimal.ZERO) <= 0) {
                logger.info("表单填写天数 {} <= 0，不发放津贴", days);
                return;
            }

            // ----------------------------------------------------
            // 步骤 2：统计本次单据的总计费人数 (默认包含报销人本人 = 1人)
            // ----------------------------------------------------
            long personCount = 1L;

            if ($travelPartnerInfo != null) {
                if ($travelPartnerInfo.getInternalTravelPartner() != null) {
                    personCount += $travelPartnerInfo.getInternalTravelPartner().size();
                }
                if ($travelPartnerInfo.getExternalTravelPartner() != null) {
                    personCount += $travelPartnerInfo.getExternalTravelPartner().size();
                }
            }
            logger.info("本次报销单最终计费参与人总数 (报销人+同行参与人) = {} 人", personCount);

            if (personCount <= 0L) {
                logger.warn("计费总人数 {} <= 0，跳过生成", personCount);
                return;
            }

            // ----------------------------------------------------
            // 步骤 3：计算整单唯一补贴总金额 = 天数 * 总人数 * 单人单日标准 (50元)
            // ----------------------------------------------------
            BigDecimal totalPeople = new BigDecimal(personCount);
            BigDecimal totalAmount = days.multiply(totalPeople).multiply($dailyRatePerPerson).setScale(2, BigDecimal.ROUND_HALF_UP);
            logger.info("整单津贴计算: {}天 * {}人 * {}元/天/人 = {}元", days, totalPeople, $dailyRatePerPerson, totalAmount);

            if (totalAmount.compareTo(BigDecimal.ZERO) <= 0) {
                logger.warn("计算所得整单津贴总额 {} <= 0，不生成明细行", totalAmount);
                return;
            }

            // ----------------------------------------------------
            // 步骤 4：构造整单唯一的 AllowanceResult 并插入内存 (报销单独立明细行)
            // ----------------------------------------------------
            DateTime consumeDate = ($submittedAt != null) ? $submittedAt : DateTime.now();
            String ccy = ($baseCcy != null && !$baseCcy.isEmpty()) ? $baseCcy : "CNY";
            String colCcy = ($collectionCcy != null && !$collectionCcy.isEmpty()) ? $collectionCcy : ccy;

            AllowanceResult result = new AllowanceResult(
                consumeDate,
                consumeDate,
                $feeCode,
                totalAmount,
                ccy,
                colCcy
            );

            insert(result);
            logger.info("🎉 成功生成并插入整单合并补贴 (纯报销单独立行): feecode={}, 总金额={}元, 天数={}, 总人数={}", $feeCode, totalAmount, days, personCount);

        } catch (Throwable t) {
            logger.error("补贴规则执行过程发生未捕获异常: {}", t.getMessage(), t);
        }
end
```
