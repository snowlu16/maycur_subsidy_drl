# custom_form_days_single_subsidy

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
declare CustomDaysSubsidyParams
    customFieldBizCode : String  // 单据表头自定义“天数”字段的组件业务编码
    feeCode : String             // 生成的补贴费用类型编码
    dailyAmount : BigDecimal     // 每天的补贴标准金额（50元）
end

// ==========================================
// 2. 初始化基础参数 (Salience 30)
// ==========================================
rule "初始化基础参数"
    salience 30
    when
        Reimburse()
    then
        // TODO: 请将 "CF_DAYS" 替换为你系统里单据表头“天数”自定义组件的实际业务编码 (如 "CF101")
        String customFieldBizCode = "CF_DAYS"; 
        // TODO: 请将 "88.004" 替换为你系统里配置的“差旅补贴”或目标补贴费用类型的编码
        String feeCode = "88.004";             
        // 每日固定补贴金额：50元
        BigDecimal dailyAmount = new BigDecimal("50");

        insert(new CustomDaysSubsidyParams(customFieldBizCode, feeCode, dailyAmount));
        logger.info("初始化表单自定义天数补贴参数完成: customFieldBizCode={}, feeCode={}, dailyAmount={}", customFieldBizCode, feeCode, dailyAmount);
end

// ==========================================
// 3. 根据表单自定义天数计算并生成整单一笔补贴 (Salience 20)
// ==========================================
rule "根据表单自定义天数计算整单补贴"
    salience 20
    when
        // 获取初始化参数
        CustomDaysSubsidyParams(
            $customFieldBizCode : customFieldBizCode,
            $feeCode : feeCode,
            $dailyAmount : dailyAmount
        );
        // 绑定单据对象及表单自定义字段集合
        $reimburse : Reimburse(
            $customFormValues : customFormValues,
            $travelRoutes : travelRoutes,
            $baseCcy : baseCcy,
            $collectionCcy : collectionCcy,
            $submittedAt : submittedAt
        );
    then
        // 1. 自单据表头的自定义字段列表中，读取填写的“出差天数/补贴天数”
        String daysStr = allowanceService.getCustomFormValue($customFormValues, $customFieldBizCode);
        logger.info("读取到单据自定义天数字段 {} 的内容为: {}", $customFieldBizCode, daysStr);

        // 2. 校验天数是否有效（非空且可解析为正数）
        if (daysStr == null || daysStr.trim().isEmpty()) {
            logger.warn("未读取到表单自定义天数值，或填报内容为空，跳过补贴生成");
            return;
        }

        BigDecimal days = BigDecimal.ZERO;
        try {
            days = new BigDecimal(daysStr.trim());
        } catch (Exception e) {
            logger.error("表单自定义天数字段内容 [{}] 无法解析为有效数字，跳过补贴生成", daysStr);
            return;
        }

        // 如果填报天数 <= 0，不生成补贴
        if (days.compareTo(BigDecimal.ZERO) <= 0) {
            logger.info("表单自定义天数为 {}，不大于0，不生成补贴", days);
            return;
        }

        // 3. 计算总补贴金额：天数 * 每天50元
        BigDecimal totalAmount = days.multiply($dailyAmount);
        logger.info("表单自定义天数 {} * 单价 {} = 补贴总金额 {}", days, $dailyAmount, totalAmount);

        // 4. 确定补贴起止时间与归属行程/消费地点
        DateTime startDate = ($submittedAt != null) ? $submittedAt : DateTime.now();
        DateTime endDate = startDate;
        String travelRouteCode = null;
        String consumeLocation = null;

        // 如果单据中存在关联的行程列表，取首尾行程的时间区间与目的地，并自动挂靠在第一段行程下（适配需要挂靠行程显示的单据配置）
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

        // 5. 构造整单唯一的 AllowanceResult 对象
        AllowanceResult result = new AllowanceResult(
            startDate,
            endDate,
            $feeCode,
            totalAmount,
            $baseCcy,
            $collectionCcy
        );

        // 如果存在行程，自动设置挂靠行程 Code 及消费地点
        if (travelRouteCode != null && !travelRouteCode.isEmpty()) {
            result.setTravelRouteCode(travelRouteCode);
        }
        if (consumeLocation != null && !consumeLocation.isEmpty()) {
            result.setConsumeLocation(consumeLocation);
        }

        // 6. 插入工作内存，供每刻引擎捕获生成明细（满足开发规范：金额>0才 insert）
        if (totalAmount.compareTo(BigDecimal.ZERO) > 0) {
            insert(result);
            logger.info("成功插入表单整单补贴记录：总天数={}, 总金额={}, 费用类型={}, 挂靠行程Code={}", days, totalAmount, $feeCode, travelRouteCode);
        }
end
```
