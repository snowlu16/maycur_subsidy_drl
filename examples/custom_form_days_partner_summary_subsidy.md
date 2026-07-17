# 表单自定义天数 + 同行人合并整单汇总计算补贴 (Custom Form Days & Travel Partners Summary)

> **场景适用**：
> 1. 补贴天数不通过单据行程计算，而是直接从报销单/申请单表头自定义字段（业务编码：`CF105`）输入；
> 2. 报销单/申请单上包含同行人（参与人）；
> 3. 补贴标准为 **每天/每人 50 元**；
> 4. 无论出差多少天、有多少同行参与人，最终全单**合并生成一笔费用明细 (`AllowanceResult`)**，费用类型编码为 `32`。

---

```drools
package rules;

import java.math.BigDecimal;
import org.joda.time.DateTime;
import org.slf4j.Logger;

import com.maycur.sdk.rule.domain.*;
import com.maycur.sdk.rule.domain.result.*;
import com.maycur.sdk.rule.service.*;

global AllowanceService allowanceService;
global Logger logger;

dialect "java"

rule "按照表单自定义天数与同行参与人数汇总计算补贴"
    when
        $reimburse : Reimburse(
            $customFormValues : customFormValues,
            $travelPartnerInfo : travelPartnerInfo,
            $baseCcy : baseCcy,
            $collectionCcy : collectionCcy,
            $submittedAt : submittedAt
        )
    then
        try {
            // ----------------------------------------------------
            // 步骤 1：读取单表头“天数”自定义字段 (CF105)
            // ----------------------------------------------------
            if ($customFormValues == null) return;
            String daysStr = allowanceService.getCustomFormValue($customFormValues, "CF105");
            if (daysStr == null || daysStr.trim().isEmpty()) return;

            BigDecimal days = BigDecimal.ZERO;
            try {
                days = new BigDecimal(daysStr.trim());
            } catch (Exception e) {
                logger.error("天数字段内容 [{}] 无法解析为数值，跳过计算", daysStr);
                return;
            }
            if (days.compareTo(BigDecimal.ZERO) <= 0) return;

            // ----------------------------------------------------
            // 步骤 2：统计同行参与人总人数 (表单参与人组件已默认包含报销人)
            // ----------------------------------------------------
            long personCount = 0L;
            if ($travelPartnerInfo != null) {
                if ($travelPartnerInfo.getInternalTravelPartner() != null) {
                    personCount += $travelPartnerInfo.getInternalTravelPartner().size();
                }
                if ($travelPartnerInfo.getExternalTravelPartner() != null) {
                    personCount += $travelPartnerInfo.getExternalTravelPartner().size();
                }
            }
            if (personCount == 0L) {
                personCount = 1L; // 兜底：若未勾选参与人组件，默认报销人自身 1 人
            }

            // ----------------------------------------------------
            // 步骤 3：计算整单金额 = 天数 * 人数 * 每天每人50元
            // ----------------------------------------------------
            BigDecimal totalAmount = days.multiply(new BigDecimal(personCount))
                                         .multiply(new BigDecimal("50"))
                                         .setScale(2, BigDecimal.ROUND_HALF_UP);
            if (totalAmount.compareTo(BigDecimal.ZERO) <= 0) return;

            // ----------------------------------------------------
            // 步骤 4：构造整单唯一补贴对象 AllowanceResult 并插入
            // ----------------------------------------------------
            DateTime consumeDate = ($submittedAt != null) ? $submittedAt : DateTime.now();
            String ccy = ($baseCcy != null && !$baseCcy.isEmpty()) ? $baseCcy : "CNY";
            String colCcy = ($collectionCcy != null && !$collectionCcy.isEmpty()) ? $collectionCcy : ccy;

            insert(new AllowanceResult(consumeDate, "32", totalAmount, ccy, colCcy));
            logger.info("🎉 报销单整单补贴生成成功: feecode=32, {}天 * {}人 * 50元 = {}元, 消费日期={}", days, personCount, totalAmount, consumeDate.toString("yyyy-MM-dd"));

        } catch (Throwable t) {
            logger.error("执行过程发生未捕获异常: {}", t.getMessage(), t);
        }
end
```
