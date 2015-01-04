include theos/makefiles/common.mk

TWEAK_NAME = AirPlayActivator
AirPlayActivator_FILES = Tweak.xm
AirPlayActivator_LIBRARIES = activator
AirPlayActivator_FRAMEWORKS = MediaPlayer
include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
