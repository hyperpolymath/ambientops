--  _pathroot TUI - Transaction Protocol Specification
--  Handles command-line transaction protocol for scripting
--
--  SPDX-License-Identifier: PMPL-1.0
--  Copyright (C) 2025 Hyper Polymath

package Pathroot_TUI.Core.Transactions is

   --  Transaction command types
   type Command_Type is
     (Cmd_Query_Env,
      Cmd_Set_Profile,
      Cmd_Create_Link,
      Cmd_Audit_Links,
      Cmd_Path_Add,
      Cmd_Path_Remove,
      Cmd_Unknown);

   --  Transaction response status
   type Response_Status is (Status_OK, Status_Error, Status_Warning);

   --  Process a transaction command
   --  Command format: PATHROOT:<command>[:param1[:param2[...]]]
   procedure Process_Command (Command : String; Devtools_Root : String);

   --  Parse command type from command string
   function Parse_Command_Type (Command : String) return Command_Type;

   --  Output JSON response
   procedure Output_Response
     (Status  : Response_Status;
      Command : String;
      Result  : String);

end Pathroot_TUI.Core.Transactions;
