include theos/makefiles/common.mk

BUNDLE_NAME = AutoAirplayPreferences
AutoAirplayPreferences_FILES = AutoAirplayPreferences.mm
AutoAirplayPreferences_INSTALL_PATH = /Library/PreferenceBundles
AutoAirplayPreferences_FRAMEWORKS = UIKit
AutoAirplayPreferences_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/AutoAirplayPreferences.plist$(ECHO_END)
