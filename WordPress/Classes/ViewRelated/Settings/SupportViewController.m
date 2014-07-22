#import "SupportViewController.h"
#import "WPWebViewController.h"
#import "ActivityLogViewController.h"
#import <UIDeviceIdentifier/UIDeviceHardware.h>
#import "WordPressAppDelegate.h"
#import <DDFileLogger.h>
#import "WPTableViewSectionFooterView.h"
#import <Helpshift/Helpshift.h>
#import <Taplytics/Taplytics.h>
#import "WPAnalytics.h"
#import <WordPress-iOS-Shared/WPStyleGuide.h>
#import "ContextManager.h"
#import "WPAccount.h"
#import "AccountService.h"
#import "BlogService.h"
#import "Blog.h"

static NSString *const UserDefaultsFeedbackEnabled = @"wp_feedback_enabled";
static NSString *const UserDefaultsHelpshiftEnabled = @"wp_helpshift_enabled";
static NSString *const UserDefaultsHelpshiftWasUsed = @"wp_helpshift_used";
static NSString * const kUsageTrackingDefaultsKey = @"usage_tracking_enabled";
static NSString * const kExtraDebugDefaultsKey = @"extra_debug";
int const kActivitySpinnerTag = 101;
int const kHelpshiftWindowTypeFAQs = 1;
int const kHelpshiftWindowTypeConversation = 2;

static NSString *const FeedbackCheckUrl = @"http://api.wordpress.org/iphoneapp/feedback-check/1.0/";

@interface SupportViewController ()

@property (nonatomic, assign) BOOL feedbackEnabled;
@property (nonatomic, assign) BOOL helpshiftEnabled;
@property (nonatomic, assign) NSInteger helpshiftUnreadCount;

@end

@implementation SupportViewController

typedef NS_ENUM(NSInteger, SettingsViewControllerSections)
{
    SettingsSectionFAQForums,
    SettingsSectionFeedback,
    SettingsSectionActivityLog,
};

+ (void)checkIfFeedbackShouldBeEnabled {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{UserDefaultsFeedbackEnabled: @YES}];
    NSURL *url = [NSURL URLWithString:FeedbackCheckUrl];
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:url];
	
	AFHTTPRequestOperation* operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
	operation.responseSerializer = [[AFJSONResponseSerializer alloc] init];
	
	[operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject)
	{
        DDLogVerbose(@"Feedback response received: %@", responseObject);
        NSNumber *feedbackEnabled = responseObject[@"feedback-enabled"];
        if (feedbackEnabled == nil) {
            feedbackEnabled = @YES;
        }
        
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setBool:feedbackEnabled.boolValue forKey:UserDefaultsFeedbackEnabled];
        [defaults synchronize];
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        DDLogError(@"Error received while checking feedback enabled status: %@", error);
        
        // Lets be optimistic and turn on feedback by default if this call doesn't work
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setBool:YES forKey:UserDefaultsFeedbackEnabled];
        [defaults synchronize];
    }];
	
	[operation start];
}

+ (void)checkIfHelpshiftShouldBeEnabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults registerDefaults:@{UserDefaultsHelpshiftEnabled:@NO}];

    BOOL userHasUsedHelpshift = [defaults boolForKey:UserDefaultsHelpshiftWasUsed];

    if (userHasUsedHelpshift) {
        [defaults setBool:YES forKey:UserDefaultsHelpshiftEnabled];
        [defaults synchronize];
        return;
    }
    
    [Taplytics runCodeExperiment:@"Helpshift Distribution" withBaseline:^(NSDictionary *variables) {
        DDLogInfo(@"Taplytics: Helpshift Experiment - Baseline Enabled");

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setBool:NO forKey:UserDefaultsHelpshiftEnabled];
        [defaults synchronize];
    } variations:@{@"Helpshift Enabled": ^(NSDictionary *variables) {
        DDLogInfo(@"Taplytics: Helpshift Experiment - Helpshift Enabled");
        
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setBool:YES forKey:UserDefaultsHelpshiftEnabled];
        [defaults synchronize];
    }}];
}

+ (void)showFromTabBar {
    SupportViewController *supportViewController = [[SupportViewController alloc] init];
    UINavigationController *aNavigationController = [[UINavigationController alloc] initWithRootViewController:supportViewController];
    aNavigationController.navigationBar.translucent = NO;
    
    if (IS_IPAD) {
        aNavigationController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        aNavigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    }
    
    UIViewController *presenter = [[WordPressAppDelegate sharedWordPressApplicationDelegate] tabBarController];
    if (presenter.presentedViewController) {
        presenter = presenter.presentedViewController;
    }
    [presenter presentViewController:aNavigationController animated:YES completion:nil];
}

- (id)init
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        self.title = NSLocalizedString(@"Support", @"");
        _feedbackEnabled = YES;
        _helpshiftEnabled = NO;
        
        _helpshiftUnreadCount = 0;
    }

    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.feedbackEnabled = [defaults boolForKey:UserDefaultsFeedbackEnabled];
    
    
    [WPStyleGuide configureColorsForView:self.view andTableView:self.tableView];
    
    [self.navigationController setNavigationBarHidden:NO animated:YES];

    if([self.navigationController.viewControllers count] == 1) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Close", @"") style:[WPStyleGuide barButtonStyleForBordered] target:self action:@selector(dismiss)];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    _helpshiftEnabled = [[self class] isHelpshiftEnabled];
    [[Helpshift sharedInstance] setDelegate:self];
    _helpshiftUnreadCount = [[Helpshift sharedInstance] getNotificationCountFromRemote:NO];

    [self.tableView reloadData];
}

+ (BOOL)isHelpshiftEnabled
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:UserDefaultsHelpshiftEnabled];
}

- (void)showLoadingSpinner {
    UIActivityIndicatorView *loading = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    loading.tag = kActivitySpinnerTag;
    loading.center = self.view.center;
    loading.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:loading];
    [loading startAnimating];
}

- (void)hideLoadingSpinner {
    [[self.view viewWithTag:kActivitySpinnerTag] removeFromSuperview];
}

- (void)prepareAndDisplayHelpshiftWindowOfType:(int)helpshiftType {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:YES forKey:UserDefaultsHelpshiftWasUsed];
    
    NSManagedObjectContext *context = [[ContextManager sharedInstance] newDerivedContext];
    AccountService *accountService = [[AccountService alloc] initWithManagedObjectContext:context];
    BlogService *blogService = [[BlogService alloc] initWithManagedObjectContext:context];
    WPAccount *defaultAccount = [accountService defaultWordPressComAccount];
    
    [Taplytics goalAchieved:@"Helpshift opened"];
    
    NSString *isWPCom = defaultAccount.isWpcom ? @"Yes" : @"No";
    NSMutableDictionary *metaData = [NSMutableDictionary dictionaryWithDictionary:@{ @"isWPCom" : isWPCom }];

    NSArray *allBlogs = [blogService blogsForAllAccounts];
    for (int i = 0; i < allBlogs.count; i++) {
        Blog *blog = allBlogs[i];
        
        NSDictionary *blogData = @{[NSString stringWithFormat:@"blog-%i-Name", i+1]: blog.blogName,
                                   [NSString stringWithFormat:@"blog-%i-ID", i+1]: blog.blogID,
                                   [NSString stringWithFormat:@"blog-%i-URL", i+1]: blog.url};
        
        [metaData addEntriesFromDictionary:blogData];
    }
    
    if (defaultAccount) {
        [self showLoadingSpinner];
        
        [metaData addEntriesFromDictionary:@{@"WPCom Username": defaultAccount.username}];
        
        [defaultAccount.restApi GET:@"me"
                         parameters:nil
                            success:^(AFHTTPRequestOperation *operation, id responseObject) {
                                [self hideLoadingSpinner];
                                
                                NSString *displayName = ([responseObject valueForKey:@"display_name"]) ? [responseObject objectForKey:@"display_name"] : nil;
                                NSString *emailAddress = ([responseObject valueForKey:@"email"]) ? [responseObject objectForKey:@"email"] : nil;

                                [self displayHelpshiftWindowOfType:helpshiftType withUsername:displayName andEmail:emailAddress andMetadata:metaData];
                            } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                                [self hideLoadingSpinner];
                                [self displayHelpshiftWindowOfType:helpshiftType withUsername:defaultAccount.username andEmail:nil andMetadata:metaData];
                            }];
    } else {
        [self displayHelpshiftWindowOfType:helpshiftType withUsername:nil andEmail:nil andMetadata:metaData];
    }
}

- (void)displayHelpshiftWindowOfType:(int)helpshiftType withUsername:(NSString*)username andEmail:(NSString*)email andMetadata:(NSDictionary*)metaData {
    [Helpshift setName:username andEmail:email];
    
    if (helpshiftType == kHelpshiftWindowTypeFAQs) {
        [[Helpshift sharedInstance] showFAQs:self withOptions:@{HSCustomMetadataKey: metaData}];
    } else if (helpshiftType == kHelpshiftWindowTypeConversation) {
        [[Helpshift sharedInstance] showConversation:self withOptions:@{HSCustomMetadataKey: metaData}];
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == SettingsSectionFAQForums) {
        return 2;
    }
    
    if (section == SettingsSectionActivityLog) {
        return 4;
    }
    
    if (section == SettingsSectionFeedback) {
        return self.feedbackEnabled ? 1 : 0;
    }

    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = nil;
    if (indexPath.section == SettingsSectionActivityLog && (indexPath.row == 1 || indexPath.row == 2)) {
        // Settings / Extra Debug
        static NSString *CellIdentifierSwitchAccessory = @"SupportViewSwitchAccessoryCell";
        cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifierSwitchAccessory];
        
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifierSwitchAccessory];
        }
        
        UISwitch *switchAccessory = [[UISwitch alloc] initWithFrame:CGRectZero];
        switchAccessory.tag = indexPath.row;
        [switchAccessory addTarget:self action:@selector(handleCellSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = switchAccessory;
    } else if (indexPath.section == SettingsSectionFAQForums && indexPath.row == 0) {
        static NSString *CellIdentifierBadgeAccessory = @"SupportViewBadgeAccessoryCell";
        cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifierBadgeAccessory];
        
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifierBadgeAccessory];
        }
    } else {
        static NSString *CellIdentifier = @"SupportViewStandardCell";
        cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
        
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:CellIdentifier];
        }
    }

    [self configureCell:cell atIndexPath:indexPath];
    
    return cell;
}

- (void)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath
{
    cell.textLabel.textAlignment = NSTextAlignmentLeft;
    [WPStyleGuide configureTableViewCell:cell];
    
    if (indexPath.section == SettingsSectionFAQForums) {
        switch (indexPath.row) {
            case 0:
                cell.textLabel.text = NSLocalizedString(@"WordPress Help Center", @"");
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

                break;
            case 1:
                if (self.helpshiftEnabled) {
                    cell.textLabel.text = NSLocalizedString(@"Contact Us", nil);
                    
                    if (self.helpshiftUnreadCount > 0) {
                        UILabel *helpshiftUnreadCountLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 50, 30)];
                        helpshiftUnreadCountLabel.layer.masksToBounds = YES;
                        helpshiftUnreadCountLabel.layer.cornerRadius = 15;
                        helpshiftUnreadCountLabel.textAlignment = NSTextAlignmentCenter;
                        helpshiftUnreadCountLabel.backgroundColor = [WPStyleGuide newKidOnTheBlockBlue];
                        helpshiftUnreadCountLabel.textColor = [UIColor whiteColor];
                        
                        helpshiftUnreadCountLabel.text = [NSString stringWithFormat:@"%i", self.helpshiftUnreadCount];
                        cell.accessoryView = helpshiftUnreadCountLabel;
                        
                        cell.accessoryType = UITableViewCellAccessoryNone;
                    } else {
                        cell.accessoryView = nil;
                        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    }
                } else {
                    cell.textLabel.text = NSLocalizedString(@"WordPress Forums", @"");
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                }
                
                break;
            default:
                // should never get here
                break;
        }
    } else if (indexPath.section == SettingsSectionFeedback) {
        cell.textLabel.text = NSLocalizedString(@"E-mail Support", @"");
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.accessoryType = UITableViewCellAccessoryNone;
        [WPStyleGuide configureTableViewActionCell:cell];
    } else if (indexPath.section == SettingsSectionActivityLog) {
        cell.textLabel.textAlignment = NSTextAlignmentLeft;

        if (indexPath.row == 0) {
            // App Version
            cell.textLabel.text = NSLocalizedString(@"Version", @"");
            NSString *appversion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
#if DEBUG
            appversion = [appversion stringByAppendingString:@" (DEV)"];
#endif
            cell.detailTextLabel.text = appversion;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 1) {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = NSLocalizedString(@"Extra Debug", @"");
            UISwitch *aSwitch = (UISwitch *)cell.accessoryView;
            aSwitch.on = [[NSUserDefaults standardUserDefaults] boolForKey:kExtraDebugDefaultsKey];
        } else if (indexPath.row == 2) {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = NSLocalizedString(@"Anonymous Usage Tracking", @"Setting for enabling anonymous usage tracking");
            UISwitch *aSwitch = (UISwitch *)cell.accessoryView;
            aSwitch.on = [[NSUserDefaults standardUserDefaults] boolForKey:kUsageTrackingDefaultsKey];
        } else if (indexPath.row == 3) {
            cell.textLabel.text = NSLocalizedString(@"Activity Logs", @"");
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    WPTableViewSectionFooterView *header = [[WPTableViewSectionFooterView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.view.bounds), 0)];
    header.title = [self titleForFooterInSection:section];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    NSString *title = [self titleForFooterInSection:section];
    return [WPTableViewSectionFooterView heightForTitle:title andWidth:CGRectGetWidth(self.view.bounds)];
}

- (NSString *)titleForFooterInSection:(NSInteger)section {
    if (section == SettingsSectionFAQForums) {
        return NSLocalizedString(@"Visit the Help Center to get answers to common questions, or visit the Forums to ask new ones.", @"");
    } else if (section == SettingsSectionActivityLog) {
        return NSLocalizedString(@"Turning on Extra Debug will log additional items to assist with us helping you with resolving a problem.", @"");
    }
    return nil;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == SettingsSectionFAQForums) {
        if (self.helpshiftEnabled) {

        }
        
        switch (indexPath.row) {
            case 0:
                if (self.helpshiftEnabled) {
                    [self prepareAndDisplayHelpshiftWindowOfType:kHelpshiftWindowTypeFAQs];
                } else {
                    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"http://ios.wordpress.org/faq"]];
                }
                
                break;
            case 1:
                if (self.helpshiftEnabled) {
                    [self prepareAndDisplayHelpshiftWindowOfType:kHelpshiftWindowTypeConversation];
                } else {
                    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"http://ios.forums.wordpress.org"]];
                }
                
                break;
            default:
                // should never get here
                break;
        }
    } else if (indexPath.section == SettingsSectionFeedback) {
        if ([MFMailComposeViewController canSendMail]) {
            MFMailComposeViewController *mailComposeViewController = [self feedbackMailViewController];
            [self presentViewController:mailComposeViewController animated:YES completion:nil];
        } else {
            [WPError showAlertWithTitle:NSLocalizedString(@"Feedback", nil) message:NSLocalizedString(@"Your device is not configured to send e-mail.", nil)];
        }
    } else if (indexPath.section == SettingsSectionActivityLog && indexPath.row == 3) {
        ActivityLogViewController *activityLogViewController = [[ActivityLogViewController alloc] init];
        [self.navigationController pushViewController:activityLogViewController animated:YES];
    }
}

#pragma mark - SupportViewController methods

- (void)handleCellSwitchChanged:(id)sender {
    UISwitch *aSwitch = (UISwitch *)sender;
    NSString *key = (aSwitch.tag == 1) ? kExtraDebugDefaultsKey : kUsageTrackingDefaultsKey;
    
    [[NSUserDefaults standardUserDefaults] setBool:aSwitch.on forKey:key];
    [NSUserDefaults resetStandardUserDefaults];
    
    if ([key isEqualToString:kUsageTrackingDefaultsKey] && aSwitch.on) {
        DDLogInfo(@"WPAnalytics session started");
        
        [WPAnalytics beginSession];
    } else if ([key isEqualToString:kUsageTrackingDefaultsKey] && !aSwitch.on) {
        DDLogInfo(@"WPAnalytics session stopped");

        [WPAnalytics endSession];
    }
}

- (MFMailComposeViewController *)feedbackMailViewController
{
    NSString *appVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:(NSString*)kCFBundleVersionKey];
    NSString *device = [UIDeviceHardware platformString];
    NSString *locale = [[NSLocale currentLocale] localeIdentifier];
    NSString *iosVersion = [[UIDevice currentDevice] systemVersion];
    
    NSMutableString *messageBody = [NSMutableString string];
    [messageBody appendFormat:@"\n\n==========\n%@\n\n", NSLocalizedString(@"Please leave your comments above this line.", @"")];
    [messageBody appendFormat:@"Device: %@\n", device];
    [messageBody appendFormat:@"App Version: %@\n", appVersion];
    [messageBody appendFormat:@"Locale: %@\n", locale];
    [messageBody appendFormat:@"OS Version: %@\n", iosVersion];
    
    WordPressAppDelegate *delegate = (WordPressAppDelegate *)[[UIApplication sharedApplication] delegate];
    DDFileLogger *fileLogger = delegate.fileLogger;
    NSArray *logFiles = fileLogger.logFileManager.sortedLogFileInfos;
    
    MFMailComposeViewController *mailComposeViewController = [[MFMailComposeViewController alloc] init];
    mailComposeViewController.mailComposeDelegate = self;
    
    [mailComposeViewController setMessageBody:messageBody isHTML:NO];
    [mailComposeViewController setSubject:@"WordPress for iOS Help Request"];
    [mailComposeViewController setToRecipients:@[@"mobile-support@automattic.com"]];

    if (logFiles.count > 0) {
        DDLogFileInfo *logFileInfo = (DDLogFileInfo *)logFiles[0];
        NSData *logData = [NSData dataWithContentsOfFile:logFileInfo.filePath];
        
        [mailComposeViewController addAttachmentData:logData mimeType:@"text/plain" fileName:@"current_log.txt"];
    }
    
    mailComposeViewController.modalPresentationCapturesStatusBarAppearance = NO;

    return mailComposeViewController;
}

- (void)dismiss {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - MFMailComposeViewControllerDelegate methods

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error
{
    switch (result) {
        case MFMailComposeResultCancelled:
            break;
        case MFMailComposeResultFailed:
            break;
        case MFMailComposeResultSaved:
        case MFMailComposeResultSent:
            break;
    }

    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Helpshift Delegate

- (void)didReceiveNotificationCount:(NSInteger)count {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.helpshiftUnreadCount = count;
    
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:SettingsSectionFAQForums];
        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    });
}

@end
