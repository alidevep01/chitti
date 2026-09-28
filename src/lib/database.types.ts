
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {

  "public": {
          Tables: {
            "app_roles": {
                  Row: {
                    "created_at": string,"role": Database["public"]['Enums']["app_role"],"user_id": string
                  }
                  Insert: {
                    "created_at"?: string,"role"?: Database["public"]['Enums']["app_role"],"user_id": string
                  }
                  Update: {
                    "created_at"?: string,"role"?: Database["public"]['Enums']["app_role"],"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "app_roles_user_id_fkey"
      columns: ["user_id"]
isOneToOne: true
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"audit_events": {
                  Row: {
                    "action": string,"actor_id": string | null,"chitti_id": string | null,"created_at": string,"detail": NonNullable<Json>,"entity_id": string | null,"entity_type": string,"id": number
                  }
                  Insert: {
                    "action": string,"actor_id"?: string | null,"chitti_id"?: string | null,"created_at"?: string,"detail"?: NonNullable<Json>,"entity_id"?: string | null,"entity_type": string,"id"?: never
                  }
                  Update: {
                    "action"?: string,"actor_id"?: string | null,"chitti_id"?: string | null,"created_at"?: string,"detail"?: NonNullable<Json>,"entity_id"?: string | null,"entity_type"?: string,"id"?: never
                  }
                  Relationships: [
                    {
      foreignKeyName: "audit_events_actor_id_fkey"
      columns: ["actor_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "audit_events_chitti_id_fkey"
      columns: ["chitti_id"]
isOneToOne: false
      referencedRelation: "chittis"
      referencedColumns: ["id"]
    }
                  ]
                },"chitti_members": {
                  Row: {
                    "chitti_id": string,"contribution_amount_paise": number,"contribution_share_bps": number,"is_admin": boolean,"joined_at": string,"payout_position": number | null,"user_id": string
                  }
                  Insert: {
                    "chitti_id": string,"contribution_amount_paise": number,"contribution_share_bps"?: number,"is_admin"?: boolean,"joined_at"?: string,"payout_position"?: number | null,"user_id": string
                  }
                  Update: {
                    "chitti_id"?: string,"contribution_amount_paise"?: number,"contribution_share_bps"?: number,"is_admin"?: boolean,"joined_at"?: string,"payout_position"?: number | null,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "chitti_members_chitti_id_fkey"
      columns: ["chitti_id"]
isOneToOne: false
      referencedRelation: "chittis"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "chitti_members_user_id_fkey"
      columns: ["user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"chittis": {
                  Row: {
                    "admin_id": string,"archived_at": string | null,"created_at": string,"description": string | null,"due_day": number,"end_date": string,"first_due_date": string,"id": string,"imported_completed_months": number,"is_imported": boolean,"locked_at": string | null,"member_count": number,"monthly_amount_paise": number,"name": string,"payee_name": string,"shuffle_scheduled_at": string | null,"start_date": string,"status": Database["public"]['Enums']["chitti_status"],"updated_at": string,"upi_id": string
                  }
                  Insert: {
                    "admin_id": string,"archived_at"?: string | null,"created_at"?: string,"description"?: string | null,"due_day": number,"end_date"?: string,"first_due_date": string,"id"?: string,"imported_completed_months"?: number,"is_imported"?: boolean,"locked_at"?: string | null,"member_count": number,"monthly_amount_paise": number,"name": string,"payee_name": string,"shuffle_scheduled_at"?: string | null,"start_date"?: string,"status"?: Database["public"]['Enums']["chitti_status"],"updated_at"?: string,"upi_id": string
                  }
                  Update: {
                    "admin_id"?: string,"archived_at"?: string | null,"created_at"?: string,"description"?: string | null,"due_day"?: number,"end_date"?: string,"first_due_date"?: string,"id"?: string,"imported_completed_months"?: number,"is_imported"?: boolean,"locked_at"?: string | null,"member_count"?: number,"monthly_amount_paise"?: number,"name"?: string,"payee_name"?: string,"shuffle_scheduled_at"?: string | null,"start_date"?: string,"status"?: Database["public"]['Enums']["chitti_status"],"updated_at"?: string,"upi_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "chittis_admin_id_fkey"
      columns: ["admin_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"contributions": {
                  Row: {
                    "amount_paise": number | null,"confirmed_at": string | null,"confirmed_on_time": boolean | null,"id": string,"member_id": string,"method": Database["public"]['Enums']["payment_method"] | null,"overdue_at": string | null,"proof_path": string | null,"reference": string | null,"reviewed_by": string | null,"round_id": string,"status": Database["public"]['Enums']["contribution_status"],"submitted_at": string | null,"updated_at": string
                  }
                  Insert: {
                    "amount_paise"?: number | null,"confirmed_at"?: string | null,"confirmed_on_time"?: boolean | null,"id"?: string,"member_id": string,"method"?: Database["public"]['Enums']["payment_method"] | null,"overdue_at"?: string | null,"proof_path"?: string | null,"reference"?: string | null,"reviewed_by"?: string | null,"round_id": string,"status"?: Database["public"]['Enums']["contribution_status"],"submitted_at"?: string | null,"updated_at"?: string
                  }
                  Update: {
                    "amount_paise"?: number | null,"confirmed_at"?: string | null,"confirmed_on_time"?: boolean | null,"id"?: string,"member_id"?: string,"method"?: Database["public"]['Enums']["payment_method"] | null,"overdue_at"?: string | null,"proof_path"?: string | null,"reference"?: string | null,"reviewed_by"?: string | null,"round_id"?: string,"status"?: Database["public"]['Enums']["contribution_status"],"submitted_at"?: string | null,"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "contributions_member_id_fkey"
      columns: ["member_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "contributions_reviewed_by_fkey"
      columns: ["reviewed_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "contributions_round_id_fkey"
      columns: ["round_id"]
isOneToOne: false
      referencedRelation: "rounds"
      referencedColumns: ["id"]
    }
                  ]
                },"invitations": {
                  Row: {
                    "accepted_at": string | null,"accepted_by": string | null,"chitti_id": string,"coowner_amount_paise": number | null,"coowner_share_bps": number | null,"coowner_source_invitation_id": string | null,"coowner_source_member_id": string | null,"created_at": string,"expires_at": string,"id": string,"invited_email": string,"invited_name": string,"invited_phone": string,"late_join": boolean,"payout_position": number | null,"status": Database["public"]['Enums']["invitation_status"],"token_hash": string
                  }
                  Insert: {
                    "accepted_at"?: string | null,"accepted_by"?: string | null,"chitti_id": string,"coowner_amount_paise"?: number | null,"coowner_share_bps"?: number | null,"coowner_source_invitation_id"?: string | null,"coowner_source_member_id"?: string | null,"created_at"?: string,"expires_at"?: string,"id"?: string,"invited_email": string,"invited_name": string,"invited_phone": string,"late_join"?: boolean,"payout_position"?: number | null,"status"?: Database["public"]['Enums']["invitation_status"],"token_hash": string
                  }
                  Update: {
                    "accepted_at"?: string | null,"accepted_by"?: string | null,"chitti_id"?: string,"coowner_amount_paise"?: number | null,"coowner_share_bps"?: number | null,"coowner_source_invitation_id"?: string | null,"coowner_source_member_id"?: string | null,"created_at"?: string,"expires_at"?: string,"id"?: string,"invited_email"?: string,"invited_name"?: string,"invited_phone"?: string,"late_join"?: boolean,"payout_position"?: number | null,"status"?: Database["public"]['Enums']["invitation_status"],"token_hash"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "invitations_accepted_by_fkey"
      columns: ["accepted_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "invitations_chitti_id_fkey"
      columns: ["chitti_id"]
isOneToOne: false
      referencedRelation: "chittis"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "invitations_coowner_source_invitation_id_fkey"
      columns: ["coowner_source_invitation_id"]
isOneToOne: false
      referencedRelation: "invitations"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "invitations_coowner_source_member_id_fkey"
      columns: ["coowner_source_member_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"notifications": {
                  Row: {
                    "created_at": string,"dedupe_key": string | null,"id": string,"kind": string,"message": string,"read_at": string | null,"route": string | null,"title": string,"user_id": string
                  }
                  Insert: {
                    "created_at"?: string,"dedupe_key"?: string | null,"id"?: string,"kind": string,"message": string,"read_at"?: string | null,"route"?: string | null,"title": string,"user_id": string
                  }
                  Update: {
                    "created_at"?: string,"dedupe_key"?: string | null,"id"?: string,"kind"?: string,"message"?: string,"read_at"?: string | null,"route"?: string | null,"title"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "notifications_user_id_fkey"
      columns: ["user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"payout_adjustments": {
                  Row: {
                    "amount_paise": number,"chitti_id": string,"confirmed_by": string | null,"contribution_id": string,"created_at": string,"id": string,"paid_at": string | null,"recipient_id": string,"reference": string | null,"round_id": string,"source_member_id": string,"status": Database["public"]['Enums']["payout_adjustment_status"],"updated_at": string
                  }
                  Insert: {
                    "amount_paise": number,"chitti_id": string,"confirmed_by"?: string | null,"contribution_id": string,"created_at"?: string,"id"?: string,"paid_at"?: string | null,"recipient_id": string,"reference"?: string | null,"round_id": string,"source_member_id": string,"status"?: Database["public"]['Enums']["payout_adjustment_status"],"updated_at"?: string
                  }
                  Update: {
                    "amount_paise"?: number,"chitti_id"?: string,"confirmed_by"?: string | null,"contribution_id"?: string,"created_at"?: string,"id"?: string,"paid_at"?: string | null,"recipient_id"?: string,"reference"?: string | null,"round_id"?: string,"source_member_id"?: string,"status"?: Database["public"]['Enums']["payout_adjustment_status"],"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "payout_adjustments_chitti_id_fkey"
      columns: ["chitti_id"]
isOneToOne: false
      referencedRelation: "chittis"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payout_adjustments_confirmed_by_fkey"
      columns: ["confirmed_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payout_adjustments_contribution_id_fkey"
      columns: ["contribution_id"]
isOneToOne: false
      referencedRelation: "contributions"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payout_adjustments_recipient_id_fkey"
      columns: ["recipient_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payout_adjustments_round_id_fkey"
      columns: ["round_id"]
isOneToOne: false
      referencedRelation: "rounds"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payout_adjustments_source_member_id_fkey"
      columns: ["source_member_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"payouts": {
                  Row: {
                    "confirmed_by": string | null,"paid_at": string | null,"reference": string | null,"round_id": string,"status": Database["public"]['Enums']["payout_status"],"updated_at": string
                  }
                  Insert: {
                    "confirmed_by"?: string | null,"paid_at"?: string | null,"reference"?: string | null,"round_id": string,"status"?: Database["public"]['Enums']["payout_status"],"updated_at"?: string
                  }
                  Update: {
                    "confirmed_by"?: string | null,"paid_at"?: string | null,"reference"?: string | null,"round_id"?: string,"status"?: Database["public"]['Enums']["payout_status"],"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "payouts_confirmed_by_fkey"
      columns: ["confirmed_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "payouts_round_id_fkey"
      columns: ["round_id"]
isOneToOne: true
      referencedRelation: "rounds"
      referencedColumns: ["id"]
    }
                  ]
                },"profiles": {
                  Row: {
                    "avatar_url": string | null,"created_at": string,"display_name": string,"email": string,"id": string,"phone": string,"updated_at": string
                  }
                  Insert: {
                    "avatar_url"?: string | null,"created_at"?: string,"display_name": string,"email": string,"id": string,"phone"?: string,"updated_at"?: string
                  }
                  Update: {
                    "avatar_url"?: string | null,"created_at"?: string,"display_name"?: string,"email"?: string,"id"?: string,"phone"?: string,"updated_at"?: string
                  }
                  Relationships: [

                  ]
                },"push_subscriptions": {
                  Row: {
                    "auth": string,"created_at": string,"endpoint": string,"id": string,"last_used_at": string,"p256dh": string,"user_agent": string | null,"user_id": string
                  }
                  Insert: {
                    "auth": string,"created_at"?: string,"endpoint": string,"id"?: string,"last_used_at"?: string,"p256dh": string,"user_agent"?: string | null,"user_id": string
                  }
                  Update: {
                    "auth"?: string,"created_at"?: string,"endpoint"?: string,"id"?: string,"last_used_at"?: string,"p256dh"?: string,"user_agent"?: string | null,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "push_subscriptions_user_id_fkey"
      columns: ["user_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"round_payout_shares": {
                  Row: {
                    "amount_paise": number,"confirmed_by": string | null,"id": string,"paid_at": string | null,"recipient_id": string,"reference": string | null,"round_id": string,"share_bps": number,"status": Database["public"]['Enums']["payout_status"],"updated_at": string
                  }
                  Insert: {
                    "amount_paise": number,"confirmed_by"?: string | null,"id"?: string,"paid_at"?: string | null,"recipient_id": string,"reference"?: string | null,"round_id": string,"share_bps": number,"status"?: Database["public"]['Enums']["payout_status"],"updated_at"?: string
                  }
                  Update: {
                    "amount_paise"?: number,"confirmed_by"?: string | null,"id"?: string,"paid_at"?: string | null,"recipient_id"?: string,"reference"?: string | null,"round_id"?: string,"share_bps"?: number,"status"?: Database["public"]['Enums']["payout_status"],"updated_at"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "round_payout_shares_confirmed_by_fkey"
      columns: ["confirmed_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "round_payout_shares_recipient_id_fkey"
      columns: ["recipient_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "round_payout_shares_round_id_fkey"
      columns: ["round_id"]
isOneToOne: false
      referencedRelation: "rounds"
      referencedColumns: ["id"]
    }
                  ]
                },"rounds": {
                  Row: {
                    "chitti_id": string,"created_at": string,"due_date": string,"id": string,"period_start_date": string,"recipient_id": string,"round_number": number,"status": Database["public"]['Enums']["round_status"]
                  }
                  Insert: {
                    "chitti_id": string,"created_at"?: string,"due_date": string,"id"?: string,"period_start_date"?: string,"recipient_id": string,"round_number": number,"status"?: Database["public"]['Enums']["round_status"]
                  }
                  Update: {
                    "chitti_id"?: string,"created_at"?: string,"due_date"?: string,"id"?: string,"period_start_date"?: string,"recipient_id"?: string,"round_number"?: number,"status"?: Database["public"]['Enums']["round_status"]
                  }
                  Relationships: [
                    {
      foreignKeyName: "rounds_chitti_id_fkey"
      columns: ["chitti_id"]
isOneToOne: false
      referencedRelation: "chittis"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "rounds_recipient_id_fkey"
      columns: ["recipient_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                },"shuffle_approvals": {
                  Row: {
                    "member_id": string,"reason": string | null,"responded_at": string | null,"shuffle_run_id": string,"status": Database["public"]['Enums']["approval_status"]
                  }
                  Insert: {
                    "member_id": string,"reason"?: string | null,"responded_at"?: string | null,"shuffle_run_id": string,"status"?: Database["public"]['Enums']["approval_status"]
                  }
                  Update: {
                    "member_id"?: string,"reason"?: string | null,"responded_at"?: string | null,"shuffle_run_id"?: string,"status"?: Database["public"]['Enums']["approval_status"]
                  }
                  Relationships: [
                    {
      foreignKeyName: "shuffle_approvals_member_id_fkey"
      columns: ["member_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "shuffle_approvals_shuffle_run_id_fkey"
      columns: ["shuffle_run_id"]
isOneToOne: false
      referencedRelation: "shuffle_runs"
      referencedColumns: ["id"]
    }
                  ]
                },"shuffle_assignments": {
                  Row: {
                    "member_id": string,"payout_position": number,"shuffle_run_id": string
                  }
                  Insert: {
                    "member_id": string,"payout_position": number,"shuffle_run_id": string
                  }
                  Update: {
                    "member_id"?: string,"payout_position"?: number,"shuffle_run_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "shuffle_assignments_member_id_fkey"
      columns: ["member_id"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "shuffle_assignments_shuffle_run_id_fkey"
      columns: ["shuffle_run_id"]
isOneToOne: false
      referencedRelation: "shuffle_runs"
      referencedColumns: ["id"]
    }
                  ]
                },"shuffle_runs": {
                  Row: {
                    "chitti_id": string,"id": string,"idempotency_key": string,"locked_at": string | null,"result_hash": string | null,"run_number": number,"started_at": string,"started_by": string,"status": Database["public"]['Enums']["shuffle_status"]
                  }
                  Insert: {
                    "chitti_id": string,"id"?: string,"idempotency_key": string,"locked_at"?: string | null,"result_hash"?: string | null,"run_number": number,"started_at"?: string,"started_by": string,"status"?: Database["public"]['Enums']["shuffle_status"]
                  }
                  Update: {
                    "chitti_id"?: string,"id"?: string,"idempotency_key"?: string,"locked_at"?: string | null,"result_hash"?: string | null,"run_number"?: number,"started_at"?: string,"started_by"?: string,"status"?: Database["public"]['Enums']["shuffle_status"]
                  }
                  Relationships: [
                    {
      foreignKeyName: "shuffle_runs_chitti_id_fkey"
      columns: ["chitti_id"]
isOneToOne: false
      referencedRelation: "chittis"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "shuffle_runs_started_by_fkey"
      columns: ["started_by"]
isOneToOne: false
      referencedRelation: "profiles"
      referencedColumns: ["id"]
    }
                  ]
                }
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "activate_imported_chitti":
{ Args: { "p_chitti_id": string }; Returns: undefined
                           },
"add_chitti_member_invitation":
{ Args: { "p_chitti_id": string,"p_email": string,"p_name": string,"p_phone": string }; Returns: Json
                           },
"add_coowner_amount_invitation":
{ Args: { "p_amount_paise": number,"p_chitti_id": string,"p_email": string,"p_name": string,"p_phone": string,"p_source_invitation_id"?: string,"p_source_member_id": string }; Returns: Json
                           },
"add_coowner_invitation":
{ Args: { "p_chitti_id": string,"p_email": string,"p_name": string,"p_phone": string,"p_share_bps": number,"p_source_invitation_id"?: string,"p_source_member_id": string }; Returns: Json
                           },
"add_coowner_invitation_active":
{ Args: { "p_chitti_id": string,"p_email": string,"p_name": string,"p_phone": string,"p_share_bps": number,"p_source_member_id": string }; Returns: Json
                           },
"add_imported_chitti_invitation":
{ Args: { "p_chitti_id": string,"p_email": string,"p_name": string,"p_payout_position": number,"p_phone": string }; Returns: Json
                           },
"bootstrap_admin":
{ Args: { "p_email": string }; Returns: string
                           },
"can_read_payment_proof":
{ Args: { "object_name": string }; Returns: boolean
                           },
"cancel_chitti":
{ Args: { "p_chitti_id": string }; Returns: undefined
                           },
"confirm_payout":
{ Args: { "p_reference"?: string,"p_round_id": string }; Returns: undefined
                           },
"confirm_payout_adjustment":
{ Args: { "p_adjustment_id": string,"p_reference"?: string }; Returns: undefined
                           },
"confirm_payout_share":
{ Args: { "p_payout_share_id": string,"p_reference"?: string }; Returns: undefined
                           },
"convert_pending_chitti_to_existing":
{ Args: { "p_chitti_id": string,"p_completed_months": number,"p_order": Json }; Returns: undefined
                           },
"convert_pending_chitti_without_shares":
{ Args: { "p_chitti_id": string,"p_completed_months": number,"p_order": Json }; Returns: undefined
                           },
"create_chitti":
{ Args: { "input": Json }; Returns: Json
                           },
"finish_round_after_shared_payout":
{ Args: { "p_round_id": string }; Returns: undefined
                           },
"get_admin_contacts":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"get_app_snapshot":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"get_app_snapshot_before_amount_shares":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"get_app_snapshot_before_pending_shares":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"get_app_snapshot_without_existing_chitti_imports":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"get_app_snapshot_without_incremental_imports":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"get_app_snapshot_without_payment_proofs":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"get_app_snapshot_without_pending_invitations":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"get_app_snapshot_without_rejection_reasons":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"get_app_snapshot_without_shared_owners":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"get_reports":
{ Args: Record<PropertyKey, never>; Returns: Json
                           },
"import_existing_chitti":
{ Args: { "input": Json }; Returns: Json
                           },
"is_admin":
{ Args: Record<PropertyKey, never>; Returns: boolean
                           },
"is_chitti_admin":
{ Args: { "p_chitti_id": string }; Returns: boolean
                           },
"is_chitti_member":
{ Args: { "p_chitti_id": string }; Returns: boolean
                           },
"mark_notification_read":
{ Args: { "p_notification_id": string }; Returns: undefined
                           },
"notify_chitti_members":
{ Args: { "p_chitti_id": string,"p_dedupe_suffix"?: string,"p_exclude"?: string,"p_kind": string,"p_message": string,"p_route": string,"p_title": string }; Returns: undefined
                           },
"process_due_reminders":
{ Args: Record<PropertyKey, never>; Returns: undefined
                           },
"redeem_invitation":
{ Args: { "p_invitation_id"?: string,"p_token"?: string }; Returns: string
                           },
"redeem_invitation_before_pending_shares":
{ Args: { "p_invitation_id"?: string,"p_token"?: string }; Returns: string
                           },
"regenerate_invitation":
{ Args: { "p_invitation_id": string }; Returns: string
                           },
"register_push_subscription":
{ Args: { "p_auth": string,"p_endpoint": string,"p_p256dh": string,"p_user_agent"?: string }; Returns: string
                           },
"respond_to_shuffle":
{ Args: { "p_accepted": boolean,"p_chitti_id": string,"p_reason"?: string }; Returns: undefined
                           },
"review_contribution":
{ Args: { "p_accepted": boolean,"p_contribution_id": string }; Returns: undefined
                           },
"run_shuffle":
{ Args: { "p_chitti_id": string,"p_idempotency_key": string }; Returns: string
                           },
"schedule_shuffle":
{ Args: { "p_chitti_id": string,"p_starts_at": string }; Returns: undefined
                           },
"submit_contribution":
{ Args: { "p_method": Database["public"]['Enums']["payment_method"],"p_reference"?: string,"p_round_id": string }; Returns: undefined
                           } |
{ Args: { "p_method": Database["public"]['Enums']["payment_method"],"p_proof_path": string,"p_reference": string,"p_round_id": string }; Returns: undefined
                           },
"swap_payout_months":
{ Args: { "p_chitti_id": string,"p_first_member_id": string,"p_second_member_id": string }; Returns: undefined
                           },
"update_invitation":
{ Args: { "p_email": string,"p_invitation_id": string,"p_name": string,"p_phone": string }; Returns: Json
                           }
          }
          Enums: {
            "app_role": "admin"|"member","approval_status": "pending"|"accepted"|"rejected","chitti_status": "draft"|"inviting"|"ready"|"shuffle_scheduled"|"awaiting_approval"|"active"|"completed"|"cancelled","contribution_status": "due"|"submitted"|"confirmed"|"rejected"|"overdue","invitation_status": "pending"|"accepted"|"revoked"|"expired","payment_method": "upi"|"cash","payout_adjustment_status": "awaiting_contribution"|"ready"|"paid","payout_status": "blocked"|"ready"|"paid","round_status": "upcoming"|"collecting"|"ready_for_payout"|"completed","shuffle_status": "pending"|"revealed"|"rejected"|"locked"
          }
          CompositeTypes: {
            [_ in never]: never
          }
        }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
      Row: infer R
    }
    ? R
    : never
  : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Insert: infer I
    }
    ? I
    : never
  : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Update: infer U
    }
    ? U
    : never
  : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
  ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
  : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never

export const Constants = {
  "public": {
          Enums: {
            "app_role": ["admin", "member"],"approval_status": ["pending", "accepted", "rejected"],"chitti_status": ["draft", "inviting", "ready", "shuffle_scheduled", "awaiting_approval", "active", "completed", "cancelled"],"contribution_status": ["due", "submitted", "confirmed", "rejected", "overdue"],"invitation_status": ["pending", "accepted", "revoked", "expired"],"payment_method": ["upi", "cash"],"payout_adjustment_status": ["awaiting_contribution", "ready", "paid"],"payout_status": ["blocked", "ready", "paid"],"round_status": ["upcoming", "collecting", "ready_for_payout", "completed"],"shuffle_status": ["pending", "revealed", "rejected", "locked"]
          }
        }
} as const
