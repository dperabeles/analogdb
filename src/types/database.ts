export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export type Database = {
  public: {
    Tables: {
      profiles: {
        Row: {
          user_id: string;
          email: string;
          display_name: string | null;
          status: "pending" | "approved" | "rejected";
          created_at: string;
          updated_at: string | null;
        };
        Insert: {
          user_id: string;
          email: string;
          display_name?: string | null;
          status?: "pending" | "approved" | "rejected";
          created_at?: string;
          updated_at?: string | null;
        };
        Update: {
          email?: string;
          display_name?: string | null;
          status?: "pending" | "approved" | "rejected";
          updated_at?: string | null;
        };
        Relationships: [];
      };
      cameras: {
        Row: {
          id: number;
          maker: string | null;
          model: string | null;
          format: string | null;
          type: string | null;
          mount: string | null;
          supports_interchangeable_lenses: boolean;
          show_in_quick_mode: boolean;
          owner_user_id: string;
          created_at: string | null;
          updated_at: string | null;
        };
        Insert: {
          id?: number;
          maker?: string | null;
          model?: string | null;
          format?: string | null;
          type?: string | null;
          mount?: string | null;
          supports_interchangeable_lenses?: boolean;
          show_in_quick_mode?: boolean;
          owner_user_id: string;
          created_at?: string | null;
          updated_at?: string | null;
        };
        Update: {
          maker?: string | null;
          model?: string | null;
          format?: string | null;
          type?: string | null;
          mount?: string | null;
          supports_interchangeable_lenses?: boolean;
          show_in_quick_mode?: boolean;
          updated_at?: string | null;
        };
        Relationships: [];
      };
      lenses: {
        Row: {
          id: number;
          maker: string;
          model: string;
          mount: string | null;
          show_in_quick_mode: boolean;
          owner_user_id: string;
          created_at: string | null;
          updated_at: string | null;
        };
        Insert: {
          id?: number;
          maker: string;
          model: string;
          mount?: string | null;
          show_in_quick_mode?: boolean;
          owner_user_id: string;
          created_at?: string | null;
          updated_at?: string | null;
        };
        Update: {
          maker?: string;
          model?: string;
          mount?: string | null;
          show_in_quick_mode?: boolean;
          updated_at?: string | null;
        };
        Relationships: [];
      };
      rolls: {
        Row: {
          id: number;
          code: string;
          camera_id: number | null;
          lens_id: number | null;
          lens: string | null;
          owner_user_id: string;
          created_at: string | null;
          updated_at: string | null;
        };
        Insert: {
          id?: number;
          code: string;
          camera_id?: number | null;
          lens_id?: number | null;
          lens?: string | null;
          owner_user_id: string;
          created_at?: string | null;
          updated_at?: string | null;
        };
        Update: {
          code?: string;
          camera_id?: number | null;
          lens_id?: number | null;
          lens?: string | null;
          updated_at?: string | null;
        };
        Relationships: [];
      };
    };
    Views: Record<string, never>;
    Functions: Record<string, never>;
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};
