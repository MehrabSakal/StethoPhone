package com.respiratory.lungaudio.adapter;

import android.content.Context;
import android.content.res.ColorStateList;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;

import androidx.annotation.NonNull;
import androidx.core.content.ContextCompat;
import androidx.recyclerview.widget.RecyclerView;

import com.respiratory.lungaudio.R;
import com.respiratory.lungaudio.databinding.ItemRecordingBinding;
import com.respiratory.lungaudio.model.RecordingItem;

import java.util.ArrayList;
import java.util.List;

public class RecordingsAdapter extends RecyclerView.Adapter<RecordingsAdapter.ViewHolder> {

    public interface OnItemClickListener {
        void onItemClick(RecordingItem item);
    }

    public interface OnPlayClickListener {
        void onPlayClick(RecordingItem item);
    }

    public interface OnDeleteClickListener {
        void onDeleteClick(RecordingItem item);
    }

    private final List<RecordingItem> items = new ArrayList<>();
    private String currentlyPlayingId = null;
    private OnItemClickListener itemClickListener;
    private OnPlayClickListener playClickListener;
    private OnDeleteClickListener deleteClickListener;

    public void setItems(List<RecordingItem> newItems) {
        items.clear();
        if (newItems != null) {
            items.addAll(newItems);
        }
        notifyDataSetChanged();
    }

    public void setCurrentlyPlayingId(String id) {
        this.currentlyPlayingId = id;
        notifyDataSetChanged();
    }

    public void setOnItemClickListener(OnItemClickListener listener) {
        this.itemClickListener = listener;
    }

    public void setOnPlayClickListener(OnPlayClickListener listener) {
        this.playClickListener = listener;
    }

    public void setOnDeleteClickListener(OnDeleteClickListener listener) {
        this.deleteClickListener = listener;
    }

    @NonNull
    @Override
    public ViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        ItemRecordingBinding binding = ItemRecordingBinding.inflate(
                LayoutInflater.from(parent.getContext()), parent, false);
        return new ViewHolder(binding);
    }

    @Override
    public void onBindViewHolder(@NonNull ViewHolder holder, int position) {
        RecordingItem item = items.get(position);
        Context ctx = holder.itemView.getContext();

        holder.binding.tvRecordingTitle.setText(item.getTitle());
        holder.binding.tvRecordingDetails.setText(
                item.getFormattedDate() + " • " + item.getFormattedDuration() + " • " + item.getFormattedSize()
        );

        if (item.hasCleaned()) {
            holder.binding.tvRecordingBadge.setVisibility(View.VISIBLE);
            holder.binding.tvRecordingBadge.setText("10x ✨");
            holder.binding.tvRecordingBadge.setBackgroundResource(R.drawable.bg_badge_clean);
            holder.binding.tvRecordingBadge.setTextColor(ContextCompat.getColor(ctx, R.color.badge_clean_text));
        } else {
            holder.binding.tvRecordingBadge.setVisibility(View.VISIBLE);
            holder.binding.tvRecordingBadge.setText("Raw 48k");
            holder.binding.tvRecordingBadge.setBackgroundResource(R.drawable.bg_badge_raw);
            holder.binding.tvRecordingBadge.setTextColor(ContextCompat.getColor(ctx, R.color.badge_raw_text));
        }

        boolean isPlaying = item.getId().equals(currentlyPlayingId);
        holder.binding.btnInlinePlay.setIconResource(isPlaying ? R.drawable.ic_pause : R.drawable.ic_play);
        if (isPlaying) {
            holder.binding.cardRecordingItem.setStrokeColor(ContextCompat.getColor(ctx, R.color.primary));
            holder.binding.cardRecordingItem.setStrokeWidth(4);
        } else {
            holder.binding.cardRecordingItem.setStrokeColor(ContextCompat.getColor(ctx, R.color.divider));
            holder.binding.cardRecordingItem.setStrokeWidth(2);
        }

        holder.binding.cardRecordingItem.setOnClickListener(v -> {
            if (itemClickListener != null) itemClickListener.onItemClick(item);
        });

        holder.binding.btnInlinePlay.setOnClickListener(v -> {
            if (playClickListener != null) playClickListener.onPlayClick(item);
        });

        holder.binding.btnDeleteRecording.setOnClickListener(v -> {
            if (deleteClickListener != null) deleteClickListener.onDeleteClick(item);
        });
    }

    @Override
    public int getItemCount() {
        return items.size();
    }

    static class ViewHolder extends RecyclerView.ViewHolder {
        final ItemRecordingBinding binding;

        ViewHolder(ItemRecordingBinding binding) {
            super(binding.getRoot());
            this.binding = binding;
        }
    }
}
