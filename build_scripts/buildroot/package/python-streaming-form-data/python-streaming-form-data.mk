################################################################################
#
# python-streaming-form-data
#
################################################################################

PYTHON_STREAMING_FORM_DATA_VERSION = 1.15.0
PYTHON_STREAMING_FORM_DATA_SOURCE = streaming-form-data-$(PYTHON_STREAMING_FORM_DATA_VERSION).tar.gz
PYTHON_STREAMING_FORM_DATA_SITE = https://files.pythonhosted.org/packages/source/s/streaming-form-data
PYTHON_STREAMING_FORM_DATA_SETUP_TYPE = setuptools
PYTHON_STREAMING_FORM_DATA_LICENSE = MIT
PYTHON_STREAMING_FORM_DATA_LICENSE_FILES = LICENSE.txt
PYTHON_STREAMING_FORM_DATA_DEPENDENCIES = python-smart-open

$(eval $(python-package))
