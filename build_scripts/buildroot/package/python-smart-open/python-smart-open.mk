################################################################################
#
# python-smart-open
#
################################################################################

PYTHON_SMART_OPEN_VERSION = 7.0.5
PYTHON_SMART_OPEN_SOURCE = smart_open-$(PYTHON_SMART_OPEN_VERSION).tar.gz
PYTHON_SMART_OPEN_SITE = https://files.pythonhosted.org/packages/source/s/smart-open
PYTHON_SMART_OPEN_SETUP_TYPE = setuptools
PYTHON_SMART_OPEN_LICENSE = MIT
PYTHON_SMART_OPEN_LICENSE_FILES = LICENSE
PYTHON_SMART_OPEN_DEPENDENCIES = python-wrapt

$(eval $(python-package))
