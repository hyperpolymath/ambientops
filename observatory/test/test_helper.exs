# SPDX-License-Identifier: MPL-2.0

# Stop application to prevent conflicts with test supervision
Application.stop(:system_observatory)

ExUnit.start()
