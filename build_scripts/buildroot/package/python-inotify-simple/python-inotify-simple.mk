################################################################################
#
# python-inotify-simple
#
################################################################################

PYTHON_INOTIFY_SIMPLE_VERSION = 1.3.5
PYTHON_INOTIFY_SIMPLE_SOURCE = inotify_simple-$(PYTHON_INOTIFY_SIMPLE_VERSION).tar.gz
PYTHON_INOTIFY_SIMPLE_SITE = https://files.pythonhosted.org/packages/source/i/inotify-simple
PYTHON_INOTIFY_SIMPLE_SETUP_TYPE = setuptools
PYTHON_INOTIFY_SIMPLE_LICENSE = BSD-3-Clause
PYTHON_INOTIFY_SIMPLE_LICENSE_FILES = LICENSE

$(eval $(python-package))
