# SPDX-License-Identifier: PMPL-1.0-or-later

# Stop application to prevent conflicts with test supervision
Application.stop(:system_observatory)

ExUnit.start()
