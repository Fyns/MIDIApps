/*
 Copyright (c) 2001-2014, Kurt Revis.  All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
 
 * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 * Neither the name of Kurt Revis, nor Snoize, nor the names of other contributors may be used to endorse or promote products derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "SMMAppController.h"

#import <CoreMIDI/CoreMIDI.h>
#import <SnoizeMIDI/SnoizeMIDI.h>
#import <Sparkle/Sparkle.h>

#import "SMMDocument.h"
#import "SMMMonitorWindowController.h"
#import "SMMPreferencesWindowController.h"


NSString* const SMMOpenWindowsForNewSourcesPreferenceKey = @"SMMOpenWindowsForNewSources";

@interface SMMAppController () <SUUpdaterDelegate>

@property (nonatomic, assign) BOOL shouldOpenUntitledDocument;
@property (nonatomic, retain) NSMutableSet *newlyAppearedSources;

@end

@implementation SMMAppController

- (void)dealloc
{
    // Appease the analyzer
    [_newlyAppearedSources release];
    [super dealloc];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    // Before CoreMIDI is initialized, make sure the spying driver is installed
    NSString *midiSpyErrorMessage = nil;
    BOOL shouldUseMIDISpy = NO;
    switch (MIDISpyInstallDriverIfNecessary()) {
        case kMIDISpyDriverAlreadyInstalled:
        case kMIDISpyDriverInstalledSuccessfully:
            shouldUseMIDISpy = YES;
            break;

        case kMIDISpyDriverCouldNotRemoveOldDriver:
            midiSpyErrorMessage = NSLocalizedStringFromTableInBundle(@"There is an old version of MIDI Monitor's driver installed, but it could not be removed. To fix this, remove the old driver. (It is probably \"Library/Audio/MIDI Drivers/MIDI Monitor.plugin\" in your home folder.)", @"MIDIMonitor", SMBundleForObject(self), "error message if old MIDI spy driver could not be removed");
            break;

        case kMIDISpyDriverInstallationFailed:
        default:
            midiSpyErrorMessage = NSLocalizedStringFromTableInBundle(@"MIDI Monitor tried to install a MIDI driver in \"Library/Audio/MIDI Drivers\" in your your home folder, but it failed. (Do the privileges allow write access?)", @"MIDIMonitor", SMBundleForObject(self), "error message if MIDI spy driver installation fails");
            break;
    }

    // Initialize CoreMIDI while the app's icon is still bouncing, so we don't have a large pause after it stops bouncing
    // but before the app's window opens.  (CoreMIDI needs to find and possibly start its server process, which can take a while.)
    if ([SMClient sharedClient] == nil) {
        NSString *title, *message, *quit;

        title = NSLocalizedStringFromTableInBundle(@"Error", @"MIDIMonitor", SMBundleForObject(self), "title of error alert");
        message = NSLocalizedStringFromTableInBundle(@"There was a problem initializing the MIDI system. To try to fix this, log out and log back in, or restart the computer.", @"MIDIMonitor", SMBundleForObject(self), "error message if MIDI initialization fails");
        quit = NSLocalizedStringFromTableInBundle(@"Quit", @"MIDIMonitor", SMBundleForObject(self), "title of quit button");

        NSRunCriticalAlertPanel(title, @"%@", quit, nil, nil, message);
        [NSApp terminate:nil];
    } else {
        // After this point, we are OK to open documents (untitled or otherwise)
        self.shouldOpenUntitledDocument = YES;
    }

    if (shouldUseMIDISpy) {
        OSStatus status;
        
        // Create our client for spying on MIDI output.
        status = MIDISpyClientCreate(&_midiSpyClient);
        if (status != noErr) {
            midiSpyErrorMessage = NSLocalizedStringFromTableInBundle(@"MIDI Monitor could not make a connection to its MIDI driver. To fix the problem, quit all MIDI applications (including this one) and launch them again.", @"MIDIMonitor", SMBundleForObject(self), "error message if MIDI spy client creation fails");
        }
    }

    if (midiSpyErrorMessage) {
        NSString *title;
        NSString *message2;

        title = NSLocalizedStringFromTableInBundle(@"Warning", @"MIDIMonitor", SMBundleForObject(self), "title of warning alert");
        message2 = NSLocalizedStringFromTableInBundle(@"MIDI Monitor will not be able to see the output of other MIDI applications, but all other features will still work.", @"MIDIMonitor", SMBundleForObject(self), "second line of warning when MIDI spy is unavailable");
        
        NSRunAlertPanel(title, @"%@\n\n%@", nil, nil, nil, midiSpyErrorMessage, message2);
    }    
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
    return self.shouldOpenUntitledDocument;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    // Listen for new source endpoints. Don't do this earlier--we only are interested in ones
    // that appear after we've been launched.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sourceEndpointsAppeared:) name:SMMIDIObjectsAppearedNotification object:[SMSourceEndpoint class]];
}

- (IBAction)showPreferences:(id)sender
{
    [[SMMPreferencesWindowController preferencesWindowController] showWindow:nil];
}

- (IBAction)showAboutBox:(id)sender
{
    NSMutableDictionary *options = [[NSMutableDictionary alloc] init];
    options[@"Version"] = @"";

    // The RTF file Credits.rtf has foreground text color = black, but that's wrong for 10.14 dark mode.
    // Similarly the font is not necessarily the systme font. Override both.
    if (@available(macOS 10.13, *)) {
        NSURL *creditsURL = [[NSBundle mainBundle] URLForResource:@"Credits" withExtension:@"rtf"];
        if (creditsURL) {
            NSMutableAttributedString *credits = [[NSMutableAttributedString alloc] initWithURL:creditsURL documentAttributes:NULL];
            NSRange range = NSMakeRange(0, credits.length);
            [credits addAttribute:NSFontAttributeName value:[NSFont labelFontOfSize:[NSFont labelFontSize]] range:range];
            if (@available(macOS 10.14, *)) {
                [credits addAttribute:NSForegroundColorAttributeName value:[NSColor labelColor] range:range];
            }
            options[NSAboutPanelOptionCredits] = credits;
            [credits release];
        }
    }

    [NSApp orderFrontStandardAboutPanelWithOptions:options];

    [options release];
}

- (IBAction)showHelp:(id)sender
{
    NSString *message = nil;
    
    NSString *path = [SMBundleForObject(self) pathForResource:@"docs" ofType:@"htmld"];
    if (path) {
        path = [path stringByAppendingPathComponent:@"index.html"];
        if (![[NSWorkspace sharedWorkspace] openFile:path]) {
            message = NSLocalizedStringFromTableInBundle(@"The help file could not be opened.", @"MIDIMonitor", SMBundleForObject(self), "error message if opening the help file fails");
        }
    } else {
        message = NSLocalizedStringFromTableInBundle(@"The help file could not be found.", @"MIDIMonitor", SMBundleForObject(self), "error message if help file can't be found");
    }

    if (message) {
        NSString *title = NSLocalizedStringFromTableInBundle(@"Error", @"MIDIMonitor", SMBundleForObject(self), "title of error alert");
        NSRunAlertPanel(title, @"%@", nil, nil, nil, message);
    }
}

- (IBAction)sendFeedback:(id)sender
{
    BOOL success = NO;

    NSString *feedbackEmailAddress = @"MIDIMonitor@snoize.com";	// Don't localize this
    NSString *feedbackEmailSubject = NSLocalizedStringFromTableInBundle(@"MIDI Monitor Feedback", @"MIDIMonitor", SMBundleForObject(self), "subject of feedback email");
    NSString *mailToURLString = [NSString stringWithFormat:@"mailto:%@?Subject=%@", feedbackEmailAddress, feedbackEmailSubject];
	mailToURLString = [(NSString*)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)mailToURLString, NULL, NULL, kCFStringEncodingUTF8) autorelease];
    NSURL *mailToURL = [NSURL URLWithString:mailToURLString];
    if (mailToURL) {
        success = [[NSWorkspace sharedWorkspace] openURL:mailToURL];
    }

    if (!success) {
        NSLog(@"Couldn't send feedback: url string was <%@>, url was <%@>", mailToURLString, mailToURL);

        NSString *title = NSLocalizedStringFromTableInBundle(@"Error", @"MIDIMonitor", SMBundleForObject(self), "title of error alert");
        NSString *message = NSLocalizedStringFromTableInBundle(@"MIDI Monitor could not ask your email application to create a new message, so you will have to do it yourself. Please send your email to this address:\n%@\nThank you!", @"MIDIMonitor", SMBundleForObject(self), "message of alert when can't send feedback email");
        
        NSRunAlertPanel(title, message, nil, nil, nil, feedbackEmailAddress);
    }
}

- (IBAction)restartMIDI:(id)sender
{
    OSStatus status = MIDIRestart();
    if (status) {
        // Something went wrong!
        NSString *message = NSLocalizedStringFromTableInBundle(@"Rescanning the MIDI system resulted in an unexpected error (%d).", @"MIDIMonitor", SMBundleForObject(self), "error message if MIDIRestart() fails");
        NSString *title = NSLocalizedStringFromTableInBundle(@"MIDI Error", @"MIDIMonitor", SMBundleForObject(self), "title of MIDI error panel");

        NSRunAlertPanel(title, message, nil, nil, nil, status);        
    }
}

#pragma mark SUUpdaterDelegate

- (BOOL)updater:(SUUpdater *)updater shouldPostponeRelaunchForUpdate:(SUAppcastItem *)item untilInvoking:(NSInvocation *)invocation
{
    // The update might contain a MIDI driver that needs to get
    // installed. In order for it to work immediately,
    // we want the MIDIServer to shut down now, so we can install
    // the driver and then trigger the MIDIServer to run again.

    // Remove our connections to the MIDIServer first:
    [SMClient disposeSharedClient];
    MIDISpyClientDispose(_midiSpyClient);
    MIDISpyClientDisposeSharedMIDIClient();

    // Wait a few seconds for the MIDIServer to hopefully shut down,
    // then relaunch for the update:
    [invocation retain];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [invocation invoke];
        [invocation release];
    });

    return YES;
}

#pragma mark Private

- (void)sourceEndpointsAppeared:(NSNotification *)notification
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:SMMOpenWindowsForNewSourcesPreferenceKey]) {
        NSArray *endpoints = [[notification userInfo] objectForKey:SMMIDIObjectsThatAppeared];

        if (!self.newlyAppearedSources) {
            self.newlyAppearedSources = [NSMutableSet set];
            [self performSelector:@selector(openWindowForNewlyAppearedSources) withObject:nil afterDelay:0.1 inModes:@[NSDefaultRunLoopMode]];
        }
        [self.newlyAppearedSources addObjectsFromArray:endpoints];
    }
}

- (void)openWindowForNewlyAppearedSources
{
    NSDocumentController *dc = [NSDocumentController sharedDocumentController];
    SMMDocument *document = [dc openUntitledDocumentAndDisplay:NO error:NULL];
    [document makeWindowControllers];
    [document setSelectedInputSources:self.newlyAppearedSources];
    [document showWindows];
    SMMMonitorWindowController *wc = document.windowControllers.firstObject;
    [wc revealInputSources:self.newlyAppearedSources];
    [document updateChangeCount:NSChangeCleared];

    self.newlyAppearedSources = nil;
}

@end
