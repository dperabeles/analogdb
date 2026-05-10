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
      film_stocks: {
        Row: {
          id: number;
          manufacturer: string;
          name: string;
          iso: number | null;
          type: "COLOR" | "B/W" | "SLIDE" | null;
          in_catalog: boolean | null;
        };
        Insert: {
          id?: number;
          manufacturer: string;
          name: string;
          iso?: number | null;
          type?: "COLOR" | "B/W" | "SLIDE" | null;
          in_catalog?: boolean | null;
        };
        Update: {
          manufacturer?: string;
          name?: string;
          iso?: number | null;
          type?: "COLOR" | "B/W" | "SLIDE" | null;
          in_catalog?: boolean | null;
        };
        Relationships: [];
      };
      labs: {
        Row: {
          id: number;
          name: string;
        };
        Insert: {
          id?: number;
          name: string;
        };
        Update: {
          name?: string;
        };
        Relationships: [];
      };
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
          film_stock_id: number | null;
          iso_pushed: number | null;
          format: number | null;
          exp_count: number | null;
          exp_taken: number | null;
          fresh: boolean | null;
          push_pull: string | null;
          camera_id: number | null;
          lens_id: number | null;
          lens: string | null;
          locations: string[] | null;
          photo_types: string[] | null;
          tags: string[] | null;
          started: string | null;
          finished: string | null;
          status: string | null;
          dev_lab_id: number | null;
          scan_lab_id: number | null;
          rating: number | null;
          notes: string | null;
          owner_user_id: string;
          created_at: string | null;
          updated_at: string | null;
        };
        Insert: {
          id?: number;
          code: string;
          film_stock_id?: number | null;
          iso_pushed?: number | null;
          format?: number | null;
          exp_count?: number | null;
          exp_taken?: number | null;
          fresh?: boolean | null;
          push_pull?: string | null;
          camera_id?: number | null;
          lens_id?: number | null;
          lens?: string | null;
          locations?: string[] | null;
          photo_types?: string[] | null;
          tags?: string[] | null;
          started?: string | null;
          finished?: string | null;
          status?: string | null;
          dev_lab_id?: number | null;
          scan_lab_id?: number | null;
          rating?: number | null;
          notes?: string | null;
          owner_user_id: string;
          created_at?: string | null;
          updated_at?: string | null;
        };
        Update: {
          code?: string;
          film_stock_id?: number | null;
          iso_pushed?: number | null;
          format?: number | null;
          exp_count?: number | null;
          exp_taken?: number | null;
          fresh?: boolean | null;
          push_pull?: string | null;
          camera_id?: number | null;
          lens_id?: number | null;
          lens?: string | null;
          locations?: string[] | null;
          photo_types?: string[] | null;
          tags?: string[] | null;
          started?: string | null;
          finished?: string | null;
          status?: string | null;
          dev_lab_id?: number | null;
          scan_lab_id?: number | null;
          rating?: number | null;
          notes?: string | null;
          updated_at?: string | null;
        };
        Relationships: [];
      };
    };
    Views: {
      rolls_flat: {
        Row: {
          id: number;
          "#": string | null;
          "FILM TYPE": string | null;
          FORMAT: string | null;
          "EXP/FRESH": string | null;
          "FILM STOCK": string | null;
          MANUFACTURER: string | null;
          ISO: number | null;
          EXP: number | null;
          MAKER: string | null;
          "MODEL NAME": string | null;
          "C. FORMAT": string | null;
          "C. TYPE": string | null;
          "C. MOUNT": string | null;
          LENS: string | null;
          "LENS MOUNT": string | null;
          LOCATIONS: string | null;
          "PHOTO TYPE": string | null;
          TAGS: string | null;
          "ISO @": number | null;
          STARTED: string | null;
          FINISHED: string | null;
          "# EXP": number | null;
          "PUSH/PULL": string | null;
          DEV: string | null;
          SCAN: string | null;
          STATUS: string | null;
          RATING: number | null;
          NOTES: string | null;
          updated_at: string | null;
          "FRAME SETTINGS": number | null;
        };
        Relationships: [];
      };
    };
    Functions: Record<string, never>;
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};
