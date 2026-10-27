################################################################################
#
# python-zipp
#
################################################################################

PYTHON_ZIPP_VERSION = 3.20.0
PYTHON_ZIPP_SOURCE = zipp-$(PYTHON_ZIPP_VERSION).tar.gz
PYTHON_ZIPP_SITE = https://files.pythonhosted.org/packages/source/z/zipp
PYTHON_ZIPP_SETUP_TYPE = setuptools
PYTHON_ZIPP_LICENSE = MIT
PYTHON_ZIPP_LICENSE_FILES = LICENSE
PYTHON_ZIPP_DEPENDENCIES = host-python-setuptools-scm

$(eval $(python-package))
