# real_1.7_含报销人和参与人_半天_打车费多次减半

```drools
package rules;

import java.util.*;
import java.math.BigDecimal;

import com.maycur.sdk.rule.domain.*;
import com.maycur.sdk.rule.domain.result.*;
import com.maycur.sdk.rule.service.*;
import org.joda.time.Days;
import org.joda.time.DateTime;
import org.joda.time.format.DateTimeFormat;
import org.slf4j.Logger;
import com.maycur.sdk.rule.service.*;


global AllowanceService allowanceService;
global Logger logger;

dialect  "mvel"



declare TravelHalfDayKeys
	dateKeys : List
	bizCode : String
	feeCode : String
	subtractFee : String
end


rule "行程-初始化TravelHalfDayKeys，用来去重"
    salience 20
    when
        Reimburse($travelRoutes:travelRoutes,$collectionCcy:collectionCcy,$baseCcy:baseCcy,$customFormValues:customFormValues);
    then
		List dateKeys = new ArrayList();
		/*  以下三个参数分别对应 补贴标准编码、补贴费用编码、扣减费用编码*/
		String bizCode="footAllowance";
		String feeCode="12345";
		String subtractFee="2020_01111";
        insert(new TravelHalfDayKeys(dateKeys,bizCode,feeCode,subtractFee));
end





rule "行程参与人-按照半天拆分"
    salience 10
    when
        Reimburse($travelRoutes:travelRoutes,$collectionCcy:collectionCcy,$baseCcy:baseCcy,$customFormValues:customFormValues,$reimEmployee:reimEmployee,$expenses:expenses);
		TravelHalfDayKeys($dateKeys:dateKeys,$bizCode:bizCode,$feeCode:feeCode,$subtractFee:subtractFee);
        $travelRecord : TravelRoute($startDate:startDate,$endDate:endDate,$allowanceStandardInfos:allowanceStandardInfos,$destination:destination,$travelPartnerInfo:travelPartnerInfo) from $travelRoutes;
		$huos: AllowanceStandardInfo(ruleBizCode==$bizCode) from $allowanceStandardInfos;
	then
		BigDecimal amount = allowanceService.getDestinationAllowanceStandard($startDate,$huos).multiply(new BigDecimal("0.5"));
		int num=1;
		BigDecimal finalAmount=new BigDecimal("0");
		List consumeTimeList = allowanceService.getTripDiffDays($travelRecord);
		for(Object o : consumeTimeList){
			String ReSdateStr=((DateTime)o).toString("yyyy-MM-dd")+"moning"+$reimEmployee.getUserCode;
		/*到达当天下午*/
		DateTime date=((DateTime)o);
		String ReEdateStra=((DateTime)o).toString("yyyy-MM-dd")+"afternonn"+$reimEmployee.getUserCode;
		if(allowanceService.isSameDay(((DateTime)o),$startDate)){
			if($startDate.getHourOfDay<12){
				if(!$dateKeys.contains(ReSdateStr)){
					$dateKeys.add(ReSdateStr);
					finalAmount=finalAmount.add(amount);
					logger.info("开始日期同一天金额早"+finalAmount);
				}
				if(!$dateKeys.contains(ReEdateStra)){
					$dateKeys.add(ReEdateStra);
					finalAmount=finalAmount.add(amount);
					logger.info("开始日期同一天金额晚"+finalAmount);
				}
			}else {
				if(!$dateKeys.contains(ReEdateStra)){
					$dateKeys.add(ReEdateStra);
					finalAmount=finalAmount.add(amount);
					logger.info("开始日期同一天金额晚"+finalAmount);
				}
			}
			logger.info("开始日期同一天金额"+finalAmount);
		}else if(allowanceService.isSameDay(((DateTime)o),$endDate)){
			if($endDate.getHourOfDay<12){
				if(!$dateKeys.contains(ReSdateStr)){
					$dateKeys.add(ReSdateStr);
					finalAmount=finalAmount.add(amount);
				}
				
			}else{
				if(!$dateKeys.contains(ReEdateStra)){
					$dateKeys.add(ReEdateStra);
					finalAmount=finalAmount.add(amount);
				}
				if(!$dateKeys.contains(ReSdateStr)){
					$dateKeys.add(ReSdateStr);
					finalAmount=finalAmount.add(amount);
				}
				
			}
			logger.info("结束日期同一天金额"+finalAmount);
		}else {
			if(!$dateKeys.contains(ReSdateStr)){
					finalAmount=finalAmount.add(amount);
					$dateKeys.add(ReSdateStr);
				}
				if(!$dateKeys.contains(ReEdateStra)){
					$dateKeys.add(ReEdateStra);
					finalAmount=finalAmount.add(amount);
				}
				
			
		}
		if(null!=$travelPartnerInfo){
		for(TravelPartner travelPartner : $travelPartnerInfo.getInternalTravelPartner()){
		String SdateStr=((DateTime)o).toString("yyyy-MM-dd")+"moning"+travelPartner.getUserCode;
		/*到达当天下午*/
		String EdateStra=((DateTime)o).toString("yyyy-MM-dd")+"afternonn"+travelPartner.getUserCode;
		if(allowanceService.isSameDay(((DateTime)o),$startDate)){
			if($startDate.getHourOfDay<12){
				if(!$dateKeys.contains(SdateStr)){
					$dateKeys.add(SdateStr);
					finalAmount=finalAmount.add(amount);
					logger.info("开始日期同一天金额早"+finalAmount);
				}
				if(!$dateKeys.contains(EdateStra)){
					$dateKeys.add(EdateStra);
					finalAmount=finalAmount.add(amount);
					logger.info("开始日期同一天金额晚"+finalAmount);
				}
			}else {
				if(!$dateKeys.contains(EdateStra)){
					$dateKeys.add(EdateStra);
					finalAmount=finalAmount.add(amount);
					logger.info("开始日期同一天金额晚"+finalAmount);
				}
			}
			logger.info("开始日期同一天金额"+finalAmount);
		}else if(allowanceService.isSameDay(((DateTime)o),$endDate)){
			if($endDate.getHourOfDay<12){
				if(!$dateKeys.contains(SdateStr)){
					$dateKeys.add(SdateStr);
					finalAmount=finalAmount.add(amount);
				}
				
			}else{
				if(!$dateKeys.contains(EdateStra)){
					$dateKeys.add(EdateStra);
					finalAmount=finalAmount.add(amount);
				}
				if(!$dateKeys.contains(SdateStr)){
					$dateKeys.add(SdateStr);
					finalAmount=finalAmount.add(amount);
				}
				
			}
			logger.info("结束日期同一天金额"+finalAmount);
		}else {
			if(!$dateKeys.contains(SdateStr)){
					finalAmount=finalAmount.add(amount);
					$dateKeys.add(SdateStr);
				}
				if(!$dateKeys.contains(EdateStra)){
					$dateKeys.add(EdateStra);
					finalAmount=finalAmount.add(amount);
				}
				
			
		}
		}
		}
		if(null != $expenses){
			for(Expense ex: $expenses){
			if(ex.getTypeBizCode.equals($subtractFee) && allowanceService.isSameDay(date,ex.getConsumeDate)){
				finalAmount=finalAmount.subtract(amount);
			}
		}
		}
		}
		
		
		
		logger.info("最后的金额----"+finalAmount);
		if(finalAmount>0){
			AllowanceResult result = new AllowanceResult($startDate,$endDate,$feeCode,finalAmount.multiply(new BigDecimal(num+"")),$baseCcy,$collectionCcy);
		insert(result);
		}
		
		
		
		
end
```
