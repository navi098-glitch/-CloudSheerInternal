/*
* Name: AccountAssetData
* Created Date: 7/11/2020
* Description: Apex controller for 'RelatedAssetList' Lightning component.
*              Retrieve and aggregate asset records related to account.
*/
public class AccountAssetData {
    @AuraEnabled
    public static List<AssetQueryResult> getAssetData(string accId){
        List<Asset> listAssets = [SELECT AccountId, 
                                         Name, 
                                         Product2Id, 
                                         Version__c, 
                                         SBQQ__PackageProductCode__c, 
                                         Quantity,
                                         SBQQ__RevisedAsset__c
                                    FROM Asset 
                                   WHERE AccountId = :accId 
                                ORDER BY AccountId, 
                                         Name, 
                                         Version__c
                                         ];
        system.debug('Asset Records: ' + listAssets);    
                              
        //Retrieve all Asset Ids
        Set<Id> setAsset = new  Set<Id>();
        Set<Id> setRevisedAsset = new  Set<Id>();
        for(Asset assetRecord : listAssets){
            setAsset.add(assetRecord.Id);
            if (assetRecord.SBQQ__RevisedAsset__c != null)
                setRevisedAsset.add(assetRecord.SBQQ__RevisedAsset__c);
        }
        
        //Retrieve all Revised Assets
        List<Asset> listRevisedAssets = [SELECT Id, 
                                                SBQQ__PackageProductCode__c
                                           FROM Asset 
                                          WHERE Id IN :setRevisedAsset];
                                          
        Map<Id, Asset> mapRevisedAssets = new Map<Id, Asset>();
        for(Asset assetRecord : listRevisedAssets){
            Id revisedAssetId = assetRecord.Id;
            if(mapRevisedAssets.get(revisedAssetId) == null){
                mapRevisedAssets.put(revisedAssetId, assetRecord);
            }
        }
        system.debug('Revised Assets: ' + mapRevisedAssets);                                 
                                          
        //Retrieve all Subscriptions related to Assets
        List<SBQQ__SubscribedAsset__c> listSubscriptions = [SELECT Id,
                                                                   SBQQ__Asset__c,
                                                                   Subscription_Start_Date__c,
                                                                   Subscription_End_Date__c,
                                                                   Contract_Term_Months__c,
                                                                   SBQQ__Subscription__r.SBQQ__Product__c
                                                              FROM SBQQ__SubscribedAsset__c
                                                             WHERE SBQQ__Asset__c IN :setAsset
                                                          ORDER BY SBQQ__Asset__c,
                                                                   Subscription_Start_Date__c,
                                                                   Subscription_End_Date__c];
                                                              
        Map<String, SBQQ__SubscribedAsset__c> mapSubscriptions = new Map<String, SBQQ__SubscribedAsset__c>();
        for(SBQQ__SubscribedAsset__c assetSub : listSubscriptions){
            string key = assetSub.SBQQ__Asset__c;
            if(mapSubscriptions.get(key) == null){
                mapSubscriptions.put(key, assetSub);
            }
        }             
        system.debug('Related Subscriptions: ' + mapSubscriptions);
        
        //Group Asset records by Account, Product, Version, PackageProductCode and Maintenance End Date                       
        Map<String, AssetQueryResult> mapAssetResults = new Map<String, AssetQueryResult>();
        Map<String, AssetQueryResult> mapFinalAssetResults = new Map<String, AssetQueryResult>();
        
        
        if(!listAssets.IsEmpty()){
            for(Asset assetRecord : listAssets){
                date startDate;
                date endDate; 
                decimal contractTerm;
                boolean includesMaintenance = false;
                boolean includesEL = false;
                boolean excludeFromList = false;
                string assetPackageProductCode = assetRecord.SBQQ__PackageProductCode__c != null ? assetRecord.SBQQ__PackageProductCode__c : '';
                
                //Determine Asset PackageProductCode
                if(assetPackageProductCode == '' &&
                    assetRecord.SBQQ__RevisedAsset__c != null){
                        if(mapRevisedAssets.get(assetRecord.SBQQ__RevisedAsset__c) != null)
                            assetPackageProductCode = mapRevisedAssets.get(assetRecord.SBQQ__RevisedAsset__c).SBQQ__PackageProductCode__c;       
                }
                
                //Check if Asset has active Subscription record
                string subscriptionKey = assetRecord.Id;
                SBQQ__SubscribedAsset__c assetSub = mapSubscriptions.get(subscriptionKey);
                if(assetSub != null &&
                   assetSub.Subscription_End_Date__c >= system.Today()){
                       startDate = assetSub.Subscription_Start_Date__c;
                       endDate = assetSub.Subscription_End_Date__c;
                       contractTerm = assetSub.Contract_Term_Months__c;
                       includesMaintenance = true;
                       includesEL = assetPackageProductCode.contains('-EL') ? true : false;
                }            
                
                //If Asset has quantity = 0 or maintenance start date in the future, exclude Asset from list
                if(assetRecord.Quantity == 0 ||
                   (startDate != null && startDate > system.today())){
                    excludeFromList = true;
                }  
                
                //Add stand-alone Asset or Asset with active maintenance in map            
                if(!excludeFromList){
                    string key = assetRecord.AccountId + '|' + 
                                 assetRecord.Product2Id + '|' + 
                                 assetRecord.Version__c + '|' + 
                                 assetPackageProductCode + '|' + 
                                 endDate;
               
                    if(mapAssetResults.get(key) != null && assetRecord.Quantity != null){
                        mapAssetResults.get(key).RollUpQty = mapAssetResults.get(key).RollUpQty + assetRecord.Quantity;
 
                        //Use earliest start date of subscription record
                        if(mapAssetResults.get(key).StartDate != null && 
                            mapSubscriptions.get(assetRecord.Id) != null &&
                            mapSubscriptions.get(assetRecord.Id).Subscription_Start_Date__c < mapAssetResults.get(key).StartDate) {
                                mapAssetResults.get(key).StartDate = mapSubscriptions.get(assetRecord.Id).Subscription_Start_Date__c;
                        }
                         
                    } else{
                        AssetQueryResult AQ = new AssetQueryResult();
                        AQ.Name = assetRecord.Name;
                        AQ.Version = assetRecord.Version__c;
                        AQ.RollUpQty = assetRecord.Quantity != null ? assetRecord.Quantity : 0;
                        AQ.StartDate = startDate;
                        AQ.EndDate = endDate;
                        AQ.Maintenance = includesMaintenance;
                        AQ.Includes_EL = includesEL;
                        AQ.Term = contractTerm;
                        mapAssetResults.put(key,AQ);
                    }
                }    
            }
            system.debug('mapAssetResults: ' + mapAssetResults);
                
            //Only add Asset records with quantity > 0 into final asset map 
            for (String assetKey : mapAssetResults.keySet()){
                if(mapAssetResults.get(assetKey).RollUpQty > 0){
                    mapFinalAssetResults.put(assetKey, mapAssetResults.get(assetKey));
                }
            }
            system.debug('mapFinalAssetResults: ' + mapFinalAssetResults);
        }
        return mapFinalAssetResults.values();
    }
    
    public class AssetQueryResult {
        @AuraEnabled
        public String Name {get; set;}
        @AuraEnabled
        public Boolean Includes_EL {get; set;}
        @AuraEnabled
        public String Version {get; set;}    
        @AuraEnabled
        public Decimal RollUpQty {get; set;}
        @AuraEnabled
        public Decimal Term {get; set;}
        @AuraEnabled
        public Boolean Maintenance {get; set;}
        @AuraEnabled
        public Date StartDate {get; set;}
        @AuraEnabled
        public Date EndDate {get; set;}
    }
}