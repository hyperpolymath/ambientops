# SPDX-License-Identifier: AGPL-3.0-or-later

# Stop application to prevent conflicts with test supervision
Application.stop(:system_observatory)

ExUnit.start()
