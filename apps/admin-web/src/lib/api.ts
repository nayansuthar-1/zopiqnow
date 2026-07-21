import { supabase, messageFor } from './supabase'

/// Every call the console makes, in one file.
///
/// All of them are RPCs, because none of these tables grant a write to the
/// browser and half of them do not grant a read either — a draft restaurant and a
/// sold-out dish are both invisible through PostgREST, even to an admin. The
/// functions are `security definer` and check `is_admin()` themselves, so what
/// follows is a transport layer and nothing more: there is no rule enforced here
/// that is not also enforced in the database.

export type RestaurantRow = {
  id: string
  name: string
  city: string | null
  is_active: boolean
  accepting_orders: boolean
  image_url: string
  menu_item_count: number
  owner_email: string | null
  published_at: string | null
  created_at: string
}

/// What the pill says. Derived, never stored — `is_active` and `published_at`
/// between them already answer it, and a status column would be a third thing
/// that could disagree with those two.
export type Status = 'live' | 'paused' | 'draft' | 'delisted'

export function statusOf(r: RestaurantRow): Status {
  if (r.is_active) return r.accepting_orders ? 'live' : 'paused'
  return r.published_at ? 'delisted' : 'draft'
}

/// Raised for anything the database refused. Its message is the sentence the RPC
/// wrote — those are meant to be read by a person and are shown unaltered.
export class ApiError extends Error {}

async function rpc<T>(fn: string, params?: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, params)
  if (error) throw new ApiError(messageFor(error))
  return data as T
}

export const api = {
  listRestaurants: () => rpc<RestaurantRow[]>('admin_list_restaurants'),

  unpublishRestaurant: (id: string) =>
    rpc<void>('admin_unpublish_restaurant', { p_id: id }),

  publishRestaurant: (id: string) =>
    rpc<void>('admin_publish_restaurant', { p_id: id }),
}
