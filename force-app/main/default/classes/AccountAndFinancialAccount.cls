public class AccountAndFinancialAccount {
    public class AUMData {
        @AuraEnabled public Decimal ratio { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public Double percentage { get; set; }
    }

    @AuraEnabled
    public static AUMData getAUMFeeToFinancialAccountData() {
        Decimal totalBalance = 0;
        Decimal totalAUMFee = 0;
        Integer totalFinancialAccounts = 0;
        List<FinServ__FinancialAccount__c> financialAccounts = [Select Id, FinServ__PrimaryOwner__c, FinServ__PrimaryOwner__r.Client_Type__c, FinServ__PrimaryOwner__r.Aum_Fee__c, FinServ__PrimaryOwner__r.Active__c , FinServ__Balance__c
        From FinServ__FinancialAccount__c 
        Where FinServ__PrimaryOwner__r.client_type__c INCLUDES('Wealth client')  and  FinServ__PrimaryOwner__r.Aum_fee__c != null and FinServ__PrimaryOwner__r.active__c = 'Yes'];

    Set<id> relatedAccountIds = new Set<id>();

    for(FinServ__FinancialAccount__c fa : financialAccounts){
    totalAUMFee += fa.FinServ__PrimaryOwner__r.Aum_fee__c;
    totalBalance += fa.FinServ__Balance__c;
    }



    AUMData result = new AUMData();
    result.ratio = (totalAUMFee  / financialAccounts.size()).setScale(2);
    result.amount = ( (totalAUMFee * totalBalance) / financialAccounts.size()).setScale(2);

    return result;

    }
    }