import { IsInt, IsOptional, IsUUID, Min } from 'class-validator';

export class OpenSessionDto {
  @IsOptional()
  @IsInt()
  @Min(1)
  guestCount?: number;

  @IsOptional()
  @IsUUID()
  customerId?: string;
}
