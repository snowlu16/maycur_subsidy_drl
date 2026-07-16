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
            logger.info("==================================================");
            logger.info("🚀 [DEBUG STEP 0] 进入规则 [根据表单自定义天数及同行人数汇总计算整单补贴] 执行核心块");
            logger.info("📦 [参数诊断] customFieldBizCode={}, feeCode={}, dailyRatePerPerson={}", $customFieldBizCode, $feeCode, $dailyRatePerPerson);
            logger.info("📦 [单据诊断] Reimburse={}", $reimburse);
            logger.info("📦 [字段检查] customFormValues是否为空: {}, travelPartnerInfo是否为空: {}, baseCcy={}, submittedAt={}", 
                ($customFormValues == null ? "是(null)" : "否(条数:" + $customFormValues.size() + ")"),
                ($travelPartnerInfo == null ? "是(null)" : "否"),
                $baseCcy, $submittedAt);

            // ----------------------------------------------------
            // 步骤 1：读取单据表头自定义“天数”字段 (CF105)
            // ----------------------------------------------------
            logger.info("🔍 [DEBUG STEP 1] 开始自 customFormValues 读取自定义天数字段 [{}]...", $customFieldBizCode);
            if ($customFormValues == null) {
                logger.error("🚨 [中断原因] 单据关联的 customFormValues 自定义字段集合为 null！无法提取字段天数！");
                return;
            }
            String daysStr = allowanceService.getCustomFormValue($customFormValues, $customFieldBizCode);
            logger.info("📄 [DEBUG STEP 1 结果] allowanceService.getCustomFormValue 返回值: [{}]", daysStr);

            if (daysStr == null || daysStr.trim().isEmpty()) {
                logger.warn("⚠️ [中断原因] 天数字段 [{}] 填报内容为空或 null，跳过本次补贴生成。", $customFieldBizCode);
                return;
            }

            BigDecimal days = BigDecimal.ZERO;
            try {
                days = new BigDecimal(daysStr.trim());
                logger.info("🔢 [DEBUG STEP 1 解析成功] 天数解析为有效数值: {}", days);
            } catch (Exception parseEx) {
                logger.error("🚨 [中断原因] 天数字段内容 [{}] 转换数值失败！报错详情: {}", daysStr, parseEx.getMessage());
                return;
            }

            if (days.compareTo(BigDecimal.ZERO) <= 0) {
                logger.warn("⚠️ [中断原因] 填报天数 {} 小于等于 0，不发放补贴。", days);
                return;
            }

            // ----------------------------------------------------
            // 步骤 2：统计本次单据的总计费人数 (默认 1 位报销人本人 + 同行人)
            // ----------------------------------------------------
            logger.info("👥 [DEBUG STEP 2] 开始统计参与计算总人数 (默认包含报销人本人 = 1人)...");
            long personCount = 1L;

            if ($travelPartnerInfo == null) {
                logger.info("ℹ️ [DEBUG STEP 2 状态] 单据头部 $travelPartnerInfo 为 null (无同行参与人组件或未填写)，总计费人数保持 = 1人");
            } else {
                logger.info("ℹ️ [DEBUG STEP 2 状态] 检测到 $travelPartnerInfo 对象不为空，提取内部与外部同行人...");
                if ($travelPartnerInfo.getInternalTravelPartner() != null) {
                    int internalSize = $travelPartnerInfo.getInternalTravelPartner().size();
                    personCount += internalSize;
                    logger.info("👨‍💼 [DEBUG STEP 2 结果] 发现内部同行参与人: {} 人", internalSize);
                } else {
                    logger.info("ℹ️ [DEBUG STEP 2 状态] 内部同行参与人列表为 null");
                }

                if ($travelPartnerInfo.getExternalTravelPartner() != null) {
                    int externalSize = $travelPartnerInfo.getExternalTravelPartner().size();
                    personCount += externalSize;
                    logger.info("🧑‍🤝‍🧑 [DEBUG STEP 2 结果] 发现外部同行参与人: {} 人", externalSize);
                } else {
                    logger.info("ℹ️ [DEBUG STEP 2 状态] 外部同行参与人列表为 null");
                }
            }
            logger.info("🎯 [DEBUG STEP 2 结论] 最终核定补贴计算人数 (报销人+参与人) = {} 人", personCount);

            if (personCount <= 0L) {
                logger.warn("⚠️ [中断原因] 最终计算总人数 {} <= 0，规则安全退出。", personCount);
                return;
            }

            // ----------------------------------------------------
            // 步骤 3：计算整单唯一补贴总金额 = 天数 * 总人数 * 单人单日标准 (50元)
            // ----------------------------------------------------
            logger.info("💰 [DEBUG STEP 3] 准备计算总补贴: {}天 * {}人 * {}元/天/人", days, personCount, $dailyRatePerPerson);
            BigDecimal totalPeople = new BigDecimal(personCount);
            BigDecimal totalAmount = days.multiply(totalPeople).multiply($dailyRatePerPerson).setScale(2, BigDecimal.ROUND_HALF_UP);
            logger.info("🧮 [DEBUG STEP 3 结果] 整单补贴总金额计算结果 = {} 元", totalAmount);

            if (totalAmount.compareTo(BigDecimal.ZERO) <= 0) {
                logger.warn("⚠️ [中断原因] 计算所得总补贴金额 {} <= 0，不执行插入。", totalAmount);
                return;
            }

            // ----------------------------------------------------
            // 步骤 4：构造并插入 AllowanceResult 对象
            // ----------------------------------------------------
            logger.info("📅 [DEBUG STEP 4] 开始构造明细行对象 AllowanceResult...");
            DateTime consumeDate = ($submittedAt != null) ? $submittedAt : DateTime.now();
            logger.info("ℹ️ [DEBUG STEP 4 时间] 明细行挂靠消费日期: {} (提交时间: {})", consumeDate, $submittedAt);

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
            logger.info("📦 [DEBUG STEP 4 对象构造完毕] AllowanceResult={}", result);

            logger.info("📥 [DEBUG STEP 5] 正在调用 insert(result) 插入内存事实对象库...");
            insert(result);
            logger.info("🎉 [DEBUG STEP 5 成功] 整笔合并补贴已成功生成并插入！本次执行完美结束。");
            logger.info("==================================================");

        } catch (Throwable t) {
            logger.error("🚨🚨🚨 [严重错误-规则核心块发生未捕获异常] 🚨🚨🚨");
            logger.error("异常类型: {}", t.getClass().getName());
            logger.error("报错提示: {}", t.getMessage(), t);
            logger.error("==================================================");
        }
end
```
