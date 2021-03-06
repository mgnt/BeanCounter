//
//  RegionSalesReportOperation.m
//  BeanCounter
//
//  Created by Craig Hockenberry on 2/29/12.
//  Copyright (c) 2012 The Iconfactory. All rights reserved.
//

#import "RegionSalesReportOperation.h"

#import "InternationalInfo.h"
#import "Product.h"
#import "Region.h"
#import "Sale.h"
#import "Earning.h"
#import "Group.h"
#import "Partner.h"

#import "DebugLog.h"

@interface RegionSalesReportOperation ()

@property (nonatomic, retain) NSManagedObjectContext *managedObjectContext;

@end


@implementation RegionSalesReportOperation

@synthesize reportCategory;
@synthesize reportCategoryFilter;
@synthesize reportShowDetails;
@synthesize reportStartDate;
@synthesize reportEndDate;
@synthesize reportVariables;

@synthesize managedObjectContext;

- (id)initWithPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)thePersistentStoreCoordinator withReportCategory:(NSUInteger)theReportCategory andCategoryFilter:(NSString *)theCategoryFilter showingDetails:(BOOL)theShowDetails from:(NSDate *)theStartDate to:(NSDate *)theEndDate delegate:(NSObject <RegionSalesReportOperationDelegate>*)theDelegate
{
	if ((self = [super init])) {
		reportCategory = theReportCategory;
		reportCategoryFilter = [theCategoryFilter copy];
		reportShowDetails = theShowDetails;
		reportStartDate = [theStartDate retain];
		reportEndDate = [theEndDate retain];
		reportVariables = nil;
		
		_unitsFormatter = [[NSNumberFormatter alloc] init];
		_unitsFormatter.numberStyle = NSNumberFormatterDecimalStyle;
		
		_salesFormatter = [[NSNumberFormatter alloc] init];
		_salesFormatter.numberStyle = NSNumberFormatterCurrencyStyle;
		
		_percentFormatter = [[NSNumberFormatter alloc] init];
		_percentFormatter.numberStyle = NSNumberFormatterPercentStyle;
		_percentFormatter.minimumFractionDigits = 1;
		
		_dateFormatter = [[NSDateFormatter alloc] init];
		_dateFormatter.dateFormat = @"MMMM yyyy";

		_persistentStoreCoordinator = thePersistentStoreCoordinator;
		_delegate = theDelegate;
	}
	
	return self;
}

- (void)dealloc
{
	[reportCategoryFilter release];
	[reportStartDate release];
	[reportEndDate release];
	[reportVariables release];
	
	[_unitsFormatter release];
	[_salesFormatter release];
	[_percentFormatter release];
	[_dateFormatter release];
	
	_persistentStoreCoordinator = nil;
	_delegate = nil;
	
	[super dealloc];
}

#define USE_COUNTS 0
#define USE_EXPRESSIONS 0

- (NSDictionary *)createSalesDictionaryInCountry:(NSString *)country withAmount:(NSDecimalNumber *)amount units:(NSNumber *)units totalUnits:(NSNumber *)totalUnits
{
	NSDecimalNumber *unitsValue = [NSDecimalNumber decimalNumberWithDecimal:[units decimalValue]];
	NSDecimalNumber *totalUnitsValue = [NSDecimalNumber decimalNumberWithDecimal:[totalUnits decimalValue]];
	NSDecimalNumber *unitPercentage = [unitsValue decimalNumberByDividingBy:totalUnitsValue];
	
	NSDecimalNumber *totalValue = [amount decimalNumberByMultiplyingBy:unitsValue]; 
	
	NSString *unitsDetailFormatted = [NSString stringWithFormat:@"%@ @ %@", [_unitsFormatter stringFromNumber:units], [_salesFormatter stringFromNumber:amount]];
	NSString *salesDetailFormatted = [_salesFormatter stringFromNumber:totalValue];
	NSString *countryDetailFormatted = country; 
	NSString *percentageDetailFormatted = [_percentFormatter stringFromNumber:unitPercentage];
	
	NSDictionary *salesDictionary = [NSDictionary dictionaryWithObjectsAndKeys:unitsDetailFormatted, @"unitsDetailFormatted", salesDetailFormatted, @"salesDetailFormatted", countryDetailFormatted, @"countryDetailFormatted", percentageDetailFormatted, @"percentageDetailFormatted", units, @"units", totalValue, @"totalValue", nil];
	
	return salesDictionary;
}

- (NSDictionary *)createProductDictionaryForRegion:(Region *)region withProduct:(Product *)product fromStartDate:(NSDate *)startDate toEndDate:(NSDate *)endDate
{
	NSDictionary *result = nil;
	
	NSArray *sales = [Sale fetchAllInManagedObjectContext:managedObjectContext forProduct:product inRegion:region startDate:startDate endDate:endDate];
	if ([sales count] > 0) {
		NSNumber *unitsSummary = [sales valueForKeyPath:@"@sum.quantity"];
		NSDecimalNumber *salesSummary = [sales valueForKeyPath:@"@sum.total"];
		
		// check the quantity sum: it can be 0 because of sales (+1) that are refunded (-1)
		if ([unitsSummary integerValue] != 0) {
			InternationalInfo *internationalInfoManager = [InternationalInfo sharedInternationalInfo];
			_salesFormatter.currencySymbol = [internationalInfoManager regionCurrencySymbolForId:region.id];
			_salesFormatter.maximumFractionDigits = [internationalInfoManager regionCurrencyDigitsForId:region.id];
			_salesFormatter.minimumFractionDigits = [internationalInfoManager regionCurrencyDigitsForId:region.id];
			
			NSString *unitsSummaryFormatted = [_unitsFormatter stringFromNumber:unitsSummary];
			NSString *salesSummaryFormatted = [_salesFormatter stringFromNumber:salesSummary];
			
			NSArray *salesArray = nil;
			if (reportShowDetails) {
				Sale *firstGroupSale = nil;
				NSNumber *unitsForCountryWithAmount = nil;
				
#if 1
				NSArray *sortDescriptors = [NSArray arrayWithObjects:[NSSortDescriptor sortDescriptorWithKey:@"country" ascending:YES], [NSSortDescriptor sortDescriptorWithKey:@"amount" ascending:NO], nil];
				sales = [sales sortedArrayUsingDescriptors:sortDescriptors];
#endif
				
				NSMutableArray *workingSalesArray = [NSMutableArray array];
				for (Sale *sale in sales) {
					BOOL createSaleDictionary = NO;
					if ([firstGroupSale.country isEqualToString:sale.country] && [firstGroupSale.amount isEqualToNumber:sale.amount]) {
						unitsForCountryWithAmount = [NSNumber numberWithInteger:[unitsForCountryWithAmount integerValue] + [sale.quantity integerValue]];
					}
					else {
						createSaleDictionary = YES;
					}
					if (createSaleDictionary) {
						if (firstGroupSale) {
							NSDictionary *salesDictionary = [self createSalesDictionaryInCountry:firstGroupSale.countryName withAmount:firstGroupSale.amount units:unitsForCountryWithAmount totalUnits:unitsSummary];
							[workingSalesArray addObject:salesDictionary];
						}
						
						firstGroupSale = sale;
						unitsForCountryWithAmount = [[sale.quantity copy] autorelease];
					}
				}
				NSDictionary *salesDictionary = [self createSalesDictionaryInCountry:firstGroupSale.countryName withAmount:firstGroupSale.amount units:unitsForCountryWithAmount totalUnits:unitsSummary];
				[workingSalesArray addObject:salesDictionary];
				
				salesArray = [workingSalesArray sortedArrayUsingDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"totalValue" ascending:NO]]];
			}
			else {
				salesArray = [NSArray array];
			}
			
			result = [NSDictionary dictionaryWithObjectsAndKeys:product, @"product", salesArray, @"salesArray", unitsSummary, @"unitsSummary", unitsSummaryFormatted, @"unitsSummaryFormatted", salesSummary, @"salesSummary", salesSummaryFormatted, @"salesSummaryFormatted", nil];
		}
	}
	
	return result;
}

- (NSArray *)createProductArrayForRegion:(Region *)region withProducts:(NSArray *)products fromStartDate:(NSDate *)startDate toEndDate:(NSDate *)endDate summaryVariables:(NSMutableDictionary *)summaryVariables
{
	NSMutableArray *productArray = [NSMutableArray array];
	
	NSNumber *unitsTotal = [NSNumber numberWithInteger:0];
	NSDecimalNumber *salesTotal = [NSDecimalNumber zero];
	
	for (Product *product in products) {
		NSDictionary *productDictionary = [self createProductDictionaryForRegion:region withProduct:product fromStartDate:startDate toEndDate:endDate];
		if (productDictionary) {
			NSNumber *unitsSummary = [productDictionary objectForKey:@"unitsSummary"];
			NSDecimalNumber *salesSummary = [productDictionary objectForKey:@"salesSummary"];
			
			if ([unitsSummary compare:[NSDecimalNumber zero]] == NSOrderedDescending) {
				// unitsSummary > 0
				unitsTotal = [NSNumber numberWithInteger:([unitsTotal integerValue] + [unitsSummary integerValue])];
				salesTotal = [salesTotal decimalNumberByAdding:salesSummary];
				
				[productArray addObject:productDictionary];
			}
		}
	}
	
	[summaryVariables setObject:unitsTotal forKey:@"unitsTotal"];
	[summaryVariables setObject:salesTotal forKey:@"salesTotal"];
	
	return [NSArray arrayWithArray:productArray];
}

- (NSDictionary *)createRegionDictionaryForRegion:(Region *)region withProducts:(NSArray *)products fromStartDate:(NSDate *)startDate toEndDate:(NSDate *)endDate
{
	NSDictionary *result = nil;
	
	NSMutableDictionary *summaryVariables = [NSMutableDictionary dictionary];
	NSArray *productArray = [self createProductArrayForRegion:region withProducts:products fromStartDate:startDate toEndDate:endDate summaryVariables:summaryVariables];
	if (productArray && [productArray count] > 0) {
		NSNumber *unitsTotal = [summaryVariables objectForKey:@"unitsTotal"];
		NSNumber *salesTotal = [summaryVariables objectForKey:@"salesTotal"];
		
		InternationalInfo *internationalInfoManager = [InternationalInfo sharedInternationalInfo];
		_salesFormatter.currencySymbol = [internationalInfoManager regionCurrencySymbolForId:region.id];
		_salesFormatter.maximumFractionDigits = [internationalInfoManager regionCurrencyDigitsForId:region.id];
		_salesFormatter.minimumFractionDigits = [internationalInfoManager regionCurrencyDigitsForId:region.id];
		
		NSString *unitsTotalFormatted = [_unitsFormatter stringFromNumber:unitsTotal];
		NSString *salesTotalFormatted = [_salesFormatter stringFromNumber:salesTotal];
		
		result = [NSDictionary dictionaryWithObjectsAndKeys:region, @"region", productArray, @"productArray", unitsTotal, @"unitsTotal", unitsTotalFormatted, @"unitsTotalFormatted", salesTotal, @"salesTotal", salesTotalFormatted, @"salesTotalFormatted", nil];
	}
	
	return result;
}

- (NSArray *)createRegionArrayWithProducts:(NSArray *)products fromStartDate:(NSDate *)startDate toEndDate:(NSDate *)endDate summaryVariables:(NSMutableDictionary *)summaryVariables
{
	NSArray *result = nil;
	
	NSNumber *categoryUnitsTotal = [NSNumber numberWithInteger:0];
	
	NSMutableArray *regionArray = [NSMutableArray array];
	
	NSArray *regions = [Region fetchAllInManagedObjectContext:managedObjectContext];
	for (Region *region in regions) {
		NSDictionary *regionDictionary = [self createRegionDictionaryForRegion:region withProducts:products fromStartDate:startDate toEndDate:endDate];
		if (regionDictionary) {
			NSNumber *unitsTotal = [regionDictionary objectForKey:@"unitsTotal"];
			
			categoryUnitsTotal = [NSNumber numberWithInteger:([categoryUnitsTotal integerValue] + [unitsTotal integerValue])];
			
			[regionArray addObject:regionDictionary];
		}
	}
	
	if ([regionArray count] > 0) {
		result = [NSArray arrayWithArray:regionArray];
		
		[summaryVariables setObject:categoryUnitsTotal forKey:@"categoryUnitsTotal"];
	}
	
	return result;
}

- (NSDictionary *)createCategoryDictionaryWithName:(NSString *)categoryName withProducts:(NSArray *)products fromStartDate:(NSDate *)startDate toEndDate:(NSDate *)endDate
{
	NSDictionary *result = nil;
	
	NSMutableDictionary *summaryVariables = [NSMutableDictionary dictionary];
	NSArray *regionArray = [self createRegionArrayWithProducts:products fromStartDate:startDate toEndDate:endDate summaryVariables:summaryVariables];
	
	if (regionArray) {
		NSDecimalNumber *categoryUnitsTotal = [summaryVariables objectForKey:@"categoryUnitsTotal"];
		
		NSString *categoryUnitsTotalFormatted = [_unitsFormatter stringFromNumber:categoryUnitsTotal];
		
		NSMutableDictionary *categoryDictionary = [NSMutableDictionary dictionary];
		if (categoryName) {
			[categoryDictionary setObject:categoryName forKey:@"categoryName"];
		}
		[categoryDictionary setObject:regionArray forKey:@"regionArray"];
		[categoryDictionary setObject:categoryUnitsTotal forKey:@"categoryUnitsTotal"];
		[categoryDictionary setObject:categoryUnitsTotalFormatted forKey:@"categoryUnitsTotalFormatted"];
		
		result = [NSDictionary dictionaryWithDictionary:categoryDictionary];
	}
	
	return result;
}

- (void)main
{
	if (self.isCancelled) {
		DebugLog(@"%s cancelled", __PRETTY_FUNCTION__);
		return;
	}

	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	
	DebugLog(@"%s report started", __PRETTY_FUNCTION__);
	NSDate *reportStart = [NSDate date];

	self.managedObjectContext = [[[NSManagedObjectContext alloc] init] autorelease];
	[managedObjectContext setPersistentStoreCoordinator:_persistentStoreCoordinator];
	
	NSNumber *grandUnitsTotal = [NSNumber numberWithInteger:0];
	NSMutableArray *categoryArray = [NSMutableArray array];

	switch (reportCategory) {
		default:
		case 0:
		{
			NSArray *allProducts = [Product fetchAllInManagedObjectContext:managedObjectContext];
			for (Product *product in allProducts) {
				NSString *categoryId = product.vendorId;
				NSString *categoryName = product.name;
				if (!reportCategoryFilter || [categoryId isEqualToString:reportCategoryFilter]) {
					NSArray *products = [NSArray arrayWithObject:product];
					NSDictionary *categoryDictionary = [self createCategoryDictionaryWithName:categoryName withProducts:products fromStartDate:reportStartDate toEndDate:reportEndDate];
					if (categoryDictionary) {
						NSNumber *categoryUnitsTotal = [categoryDictionary objectForKey:@"categoryUnitsTotal"];
						grandUnitsTotal = [NSNumber numberWithInteger:([grandUnitsTotal integerValue] + [categoryUnitsTotal integerValue])];
						[categoryArray addObject:categoryDictionary];
					}
				}
			}
		}
			break;
		case 1:
		{
			NSArray *allGroups = [Group fetchAllInManagedObjectContext:managedObjectContext];
			for (Group *group in allGroups) {
				NSString *categoryId = group.groupId;
				NSString *categoryName = group.name;
				if (!reportCategoryFilter || [categoryId isEqualToString:reportCategoryFilter]) {
					NSArray *products = [Product fetchAllInManagedObjectContext:managedObjectContext forGroup:group];
					NSDictionary *categoryDictionary = [self createCategoryDictionaryWithName:categoryName withProducts:products fromStartDate:reportStartDate toEndDate:reportEndDate];
					if (categoryDictionary) {
						NSNumber *categoryUnitsTotal = [categoryDictionary objectForKey:@"categoryUnitsTotal"];
						grandUnitsTotal = [NSNumber numberWithInteger:([grandUnitsTotal integerValue] + [categoryUnitsTotal integerValue])];
						[categoryArray addObject:categoryDictionary];
					}
				}
			}
			
			{
				NSString *categoryId = @"__NONE__";
				NSString *categoryName = @"No Product Group";
				if (!reportCategoryFilter || [categoryId isEqualToString:reportCategoryFilter]) {
					NSArray *products = [Product fetchAllWithoutGroupInManagedObjectContext:managedObjectContext];
					NSDictionary *categoryDictionary = [self createCategoryDictionaryWithName:categoryName withProducts:products fromStartDate:reportStartDate toEndDate:reportEndDate];
					if (categoryDictionary) {
						NSNumber *categoryUnitsTotal = [categoryDictionary objectForKey:@"categoryUnitsTotal"];
						grandUnitsTotal = [NSNumber numberWithInteger:([grandUnitsTotal integerValue] + [categoryUnitsTotal integerValue])];
						[categoryArray addObject:categoryDictionary];
					}
				}
			}
		}
			break;
		case 2:
		{
			NSArray *allPartners = [Partner fetchAllInManagedObjectContext:managedObjectContext];
			for (Partner *partner in allPartners) {
				NSString *categoryId = partner.partnerId;
				NSString *categoryName = partner.name;
				if (!reportCategoryFilter || [categoryId isEqualToString:reportCategoryFilter]) {
					NSArray *products = [Product fetchAllInManagedObjectContext:managedObjectContext forPartner:partner];
					NSDictionary *categoryDictionary = [self createCategoryDictionaryWithName:categoryName withProducts:products fromStartDate:reportStartDate toEndDate:reportEndDate];
					if (categoryDictionary) {
						NSNumber *categoryUnitsTotal = [categoryDictionary objectForKey:@"categoryUnitsTotal"];
						grandUnitsTotal = [NSNumber numberWithInteger:([grandUnitsTotal integerValue] + [categoryUnitsTotal integerValue])];
						[categoryArray addObject:categoryDictionary];
					}
				}
			}
			
			{
				NSString *categoryId = @"__NONE__";
				NSString *categoryName = @"No Partner";
				if (!reportCategoryFilter || [categoryId isEqualToString:reportCategoryFilter]) {
					NSArray *products = [Product fetchAllWithoutPartnerInManagedObjectContext:managedObjectContext];
					NSDictionary *categoryDictionary = [self createCategoryDictionaryWithName:categoryName withProducts:products fromStartDate:reportStartDate toEndDate:reportEndDate];
					if (categoryDictionary) {
						NSNumber *categoryUnitsTotal = [categoryDictionary objectForKey:@"categoryUnitsTotal"];
						grandUnitsTotal = [NSNumber numberWithInteger:([grandUnitsTotal integerValue] + [categoryUnitsTotal integerValue])];
						[categoryArray addObject:categoryDictionary];
					}
				}
			}			
		}
			break;
	}

	if (! self.isCancelled) {
		NSString *reportTitle = [NSString stringWithFormat:@"%@ - %@", [_dateFormatter stringFromDate:reportStartDate], [_dateFormatter stringFromDate:reportEndDate]];
		
		NSMutableDictionary *variables = [NSMutableDictionary dictionary];
		[variables setObject:reportTitle forKey:@"reportTitle"];
		[variables setObject:categoryArray forKey:@"categoryArray"];
		if (! reportCategoryFilter) {
			NSString *grandUnitsTotalFormatted = [_unitsFormatter stringFromNumber:grandUnitsTotal];
			[variables setObject:grandUnitsTotalFormatted forKey:@"grandUnitsTotalFormatted"];
		}
		
		self.reportVariables = [NSDictionary dictionaryWithDictionary:variables];
		
		[_delegate performSelectorOnMainThread:@selector(regionSalesReportOperationCompleted:) withObject:self waitUntilDone:YES];
	}
	
	self.managedObjectContext = nil;
	
	NSDate *reportEnd = [NSDate date];
	DebugLog(@"%s report generated in %f seconds", __PRETTY_FUNCTION__, [reportEnd timeIntervalSinceDate:reportStart]);

	[pool drain];
}

@end
