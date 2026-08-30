LOCAL_PATH := $(call my-dir)

ifeq ($(TARGET_DEVICE),A37f)
include $(call all-subdir-makefiles,$(LOCAL_PATH))
endif
