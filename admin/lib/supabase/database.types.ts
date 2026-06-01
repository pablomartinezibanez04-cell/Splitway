export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      admin_audit_log: {
        Row: {
          action: string
          admin_id: string | null
          created_at: string
          details: Json | null
          id: string
          target_id: string
          target_type: string
        }
        Insert: {
          action: string
          admin_id?: string | null
          created_at?: string
          details?: Json | null
          id?: string
          target_id: string
          target_type: string
        }
        Update: {
          action?: string
          admin_id?: string | null
          created_at?: string
          details?: Json | null
          id?: string
          target_id?: string
          target_type?: string
        }
        Relationships: []
      }
      app_logs: {
        Row: {
          app_version: string
          context: Json | null
          device_model: string
          error: string | null
          id: string
          level: string
          message: string
          platform: string
          stack_trace: string | null
          tag: string
          timestamp: string
          user_id: string | null
        }
        Insert: {
          app_version: string
          context?: Json | null
          device_model: string
          error?: string | null
          id: string
          level: string
          message: string
          platform: string
          stack_trace?: string | null
          tag: string
          timestamp: string
          user_id?: string | null
        }
        Update: {
          app_version?: string
          context?: Json | null
          device_model?: string
          error?: string | null
          id?: string
          level?: string
          message?: string
          platform?: string
          stack_trace?: string | null
          tag?: string
          timestamp?: string
          user_id?: string | null
        }
        Relationships: []
      }
      free_ride_telemetry: {
        Row: {
          accuracy_m: number | null
          altitude_m: number | null
          bearing_deg: number | null
          free_ride_id: string
          lat: number
          lng: number
          owner_id: string
          speed_mps: number | null
          ts: string
        }
        Insert: {
          accuracy_m?: number | null
          altitude_m?: number | null
          bearing_deg?: number | null
          free_ride_id: string
          lat: number
          lng: number
          owner_id: string
          speed_mps?: number | null
          ts: string
        }
        Update: {
          accuracy_m?: number | null
          altitude_m?: number | null
          bearing_deg?: number | null
          free_ride_id?: string
          lat?: number
          lng?: number
          owner_id?: string
          speed_mps?: number | null
          ts?: string
        }
        Relationships: [
          {
            foreignKeyName: "free_ride_telemetry_free_ride_id_fkey"
            columns: ["free_ride_id"]
            isOneToOne: false
            referencedRelation: "free_rides"
            referencedColumns: ["id"]
          },
        ]
      }
      free_rides: {
        Row: {
          avg_speed_mps: number
          description: string | null
          ended_at: string | null
          id: string
          location_label: string | null
          max_speed_mps: number
          name: string | null
          owner_id: string
          started_at: string
          status: string
          total_distance_m: number
          updated_at: string
          vehicle_id: string | null
        }
        Insert: {
          avg_speed_mps?: number
          description?: string | null
          ended_at?: string | null
          id: string
          location_label?: string | null
          max_speed_mps?: number
          name?: string | null
          owner_id: string
          started_at: string
          status: string
          total_distance_m?: number
          updated_at?: string
          vehicle_id?: string | null
        }
        Update: {
          avg_speed_mps?: number
          description?: string | null
          ended_at?: string | null
          id?: string
          location_label?: string | null
          max_speed_mps?: number
          name?: string | null
          owner_id?: string
          started_at?: string
          status?: string
          total_distance_m?: number
          updated_at?: string
          vehicle_id?: string | null
        }
        Relationships: []
      }
      profiles: {
        Row: {
          avatar_url: string | null
          bio: string | null
          created_at: string
          date_of_birth: string | null
          id: string
          nickname: string
          nickname_changed_at: string
          role: string
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          bio?: string | null
          created_at?: string
          date_of_birth?: string | null
          id: string
          nickname: string
          nickname_changed_at?: string
          role?: string
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          bio?: string | null
          created_at?: string
          date_of_birth?: string | null
          id?: string
          nickname?: string
          nickname_changed_at?: string
          role?: string
          updated_at?: string
        }
        Relationships: []
      }
      route_templates: {
        Row: {
          created_at: string
          description: string | null
          difficulty: string
          elevation_range_m: number | null
          id: string
          location_label: string | null
          name: string
          owner_id: string
          path_json: Json
          start_finish_gate_json: Json
          thumbnail_url: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          difficulty?: string
          elevation_range_m?: number | null
          id: string
          location_label?: string | null
          name: string
          owner_id: string
          path_json: Json
          start_finish_gate_json: Json
          thumbnail_url?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          difficulty?: string
          elevation_range_m?: number | null
          id?: string
          location_label?: string | null
          name?: string
          owner_id?: string
          path_json?: Json
          start_finish_gate_json?: Json
          thumbnail_url?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      sectors: {
        Row: {
          gate_json: Json
          id: string
          label: string
          order_index: number
          route_id: string
        }
        Insert: {
          gate_json: Json
          id: string
          label: string
          order_index: number
          route_id: string
        }
        Update: {
          gate_json?: Json
          id?: string
          label?: string
          order_index?: number
          route_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "sectors_route_id_fkey"
            columns: ["route_id"]
            isOneToOne: false
            referencedRelation: "route_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      session_runs: {
        Row: {
          avg_speed_mps: number
          ended_at: string | null
          id: string
          lap_summaries_json: Json
          max_speed_mps: number
          owner_id: string
          route_id: string
          sector_summaries_json: Json
          started_at: string
          status: string
          total_distance_m: number
          updated_at: string
          vehicle_id: string | null
        }
        Insert: {
          avg_speed_mps?: number
          ended_at?: string | null
          id: string
          lap_summaries_json?: Json
          max_speed_mps?: number
          owner_id: string
          route_id: string
          sector_summaries_json?: Json
          started_at: string
          status: string
          total_distance_m?: number
          updated_at?: string
          vehicle_id?: string | null
        }
        Update: {
          avg_speed_mps?: number
          ended_at?: string | null
          id?: string
          lap_summaries_json?: Json
          max_speed_mps?: number
          owner_id?: string
          route_id?: string
          sector_summaries_json?: Json
          started_at?: string
          status?: string
          total_distance_m?: number
          updated_at?: string
          vehicle_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "session_runs_route_id_fkey"
            columns: ["route_id"]
            isOneToOne: false
            referencedRelation: "route_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      speed_sessions: {
        Row: {
          countdown_seconds: number
          created_at: string
          deleted_at: string | null
          finished_at: string | null
          id: string
          is_partial: boolean
          name: string
          results: Json
          selected_metrics: string[]
          started_at: string
          updated_at: string
          user_id: string
          vehicle_id: string | null
        }
        Insert: {
          countdown_seconds: number
          created_at?: string
          deleted_at?: string | null
          finished_at?: string | null
          id?: string
          is_partial?: boolean
          name: string
          results?: Json
          selected_metrics: string[]
          started_at: string
          updated_at?: string
          user_id: string
          vehicle_id?: string | null
        }
        Update: {
          countdown_seconds?: number
          created_at?: string
          deleted_at?: string | null
          finished_at?: string | null
          id?: string
          is_partial?: boolean
          name?: string
          results?: Json
          selected_metrics?: string[]
          started_at?: string
          updated_at?: string
          user_id?: string
          vehicle_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "speed_sessions_vehicle_id_fkey"
            columns: ["vehicle_id"]
            isOneToOne: false
            referencedRelation: "vehicles"
            referencedColumns: ["id"]
          },
        ]
      }
      telemetry_points: {
        Row: {
          accuracy_m: number | null
          altitude_m: number | null
          bearing_deg: number | null
          lat: number
          lng: number
          owner_id: string
          session_id: string
          speed_mps: number | null
          ts: string
        }
        Insert: {
          accuracy_m?: number | null
          altitude_m?: number | null
          bearing_deg?: number | null
          lat: number
          lng: number
          owner_id: string
          session_id: string
          speed_mps?: number | null
          ts: string
        }
        Update: {
          accuracy_m?: number | null
          altitude_m?: number | null
          bearing_deg?: number | null
          lat?: number
          lng?: number
          owner_id?: string
          session_id?: string
          speed_mps?: number | null
          ts?: string
        }
        Relationships: [
          {
            foreignKeyName: "telemetry_points_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "session_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      vehicles: {
        Row: {
          created_at: string
          drivetrain: string | null
          horsepower: number | null
          id: string
          model: string | null
          name: string
          notes: string | null
          photo_url: string | null
          torque_nm: number | null
          type: string
          user_id: string
          weight_kg: number | null
          year: number | null
        }
        Insert: {
          created_at?: string
          drivetrain?: string | null
          horsepower?: number | null
          id?: string
          model?: string | null
          name: string
          notes?: string | null
          photo_url?: string | null
          torque_nm?: number | null
          type?: string
          user_id: string
          weight_kg?: number | null
          year?: number | null
        }
        Update: {
          created_at?: string
          drivetrain?: string | null
          horsepower?: number | null
          id?: string
          model?: string | null
          name?: string
          notes?: string | null
          photo_url?: string | null
          torque_nm?: number | null
          type?: string
          user_id?: string
          weight_kg?: number | null
          year?: number | null
        }
        Relationships: []
      }
    }
    Views: {
      admin_users_view: {
        Row: {
          avatar_url: string | null
          banned_until: string | null
          email: string | null
          id: string | null
          last_activity: string | null
          nickname: string | null
          profile_created_at: string | null
          role: string | null
          routes_count: number | null
          sessions_count: number | null
          signup_date: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      find_email_by_user_id: { Args: { p_user_id: string }; Returns: string }
      find_user_id_by_email: { Args: { p_email: string }; Returns: string }
      update_nickname: { Args: { new_nickname: string }; Returns: undefined }
      upsert_free_ride_with_telemetry: {
        Args: {
          p_avg_speed_mps: number
          p_description: string
          p_ended_at: string
          p_id: string
          p_location_label: string
          p_max_speed_mps: number
          p_name: string
          p_points: Json
          p_started_at: string
          p_status: string
          p_total_distance_m: number
          p_updated_at: string
          p_vehicle_id?: string
        }
        Returns: undefined
      }
      upsert_session_with_telemetry: {
        Args: {
          p_avg_speed_mps: number
          p_ended_at: string
          p_id: string
          p_lap_summaries: Json
          p_max_speed_mps: number
          p_points: Json
          p_route_id: string
          p_sector_summaries: Json
          p_started_at: string
          p_status: string
          p_total_distance_m: number
          p_updated_at: string
          p_vehicle_id?: string
        }
        Returns: undefined
      }
      user_has_password: { Args: never; Returns: boolean }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

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
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
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
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
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
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
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
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
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
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
